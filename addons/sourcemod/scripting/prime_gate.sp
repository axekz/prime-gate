#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <admin>
#include <gokz/core>
#include <SteamWorks>

// Declare gokz-global natives we need (to avoid including GlobalAPI)
native bool GOKZ_GL_GetAPIKeyValid();
native void GOKZ_GL_UpdatePoints(int client = -1, int mode = -1);
native int GOKZ_GL_GetRankPoints(int client, int mode);

#define APPID_CS_PRIME 624820  // CS2 Full Edition / legacy Prime

ConVar gCvarEnforce, gCvarAllowAdmins, gCvarWhitelist, gCvarKickMsg, gCvarPointsThreshold;
bool g_bPendingCheck[MAXPLAYERS + 1];

public Plugin myinfo =
{
    name        = "GOKZ Prime Gate",
    author      = "Cinyan10",
    description = "Blocks non-Prime unless whitelisted/admin",
    version     = "1.1.0",
    url         = "https://axekz.com/"
};

public void OnPluginStart()
{
    gCvarEnforce      = CreateConVar("sm_prime_enforce", "1", "Enforce Prime-only join (1/0)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    gCvarAllowAdmins  = CreateConVar("sm_prime_allow_admins", "1", "Admins with flag 'b' bypass (1/0)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    gCvarWhitelist    = CreateConVar("sm_prime_whitelist", "1", "Enable file whitelist (1/0)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    gCvarKickMsg = CreateConVar("sm_prime_kick_message", "You need a Prime account to play on this server.", "Kick message (points threshold will be appended automatically)", FCVAR_NOTIFY);
    gCvarPointsThreshold = CreateConVar("sm_prime_points_threshold", "50000", "Minimum points in any mode to bypass Prime requirement", FCVAR_NOTIFY, true, 0.0);

    RegAdminCmd("sm_prime_reload", Cmd_ReloadWL, ADMFLAG_GENERIC, "Reload prime whitelist");
    RegAdminCmd("sm_padd", Cmd_WLAdd, ADMFLAG_GENERIC, "Add player to Prime whitelist: sm_pwladd <steamid64|steam2>");
    RegAdminCmd("sm_pdel", Cmd_WLDel, ADMFLAG_GENERIC, "Remove player from Prime whitelist: sm_pwldel <steamid64|steam2>");
    RegAdminCmd("sm_prime_whitelist_add", Cmd_WLAdd, ADMFLAG_GENERIC, "Add player to Prime whitelist: sm_prime_whitelist_add <steamid64|steam2>");
    RegAdminCmd("sm_prime_whitelist_del", Cmd_WLDel, ADMFLAG_GENERIC, "Remove player from Prime whitelist: sm_prime_whitelist_del <steamid64|steam2>");

    char path[PLATFORM_MAX_PATH];
    WL_Path(path, sizeof(path));
    if (!FileExists(path))
    {
        File f = OpenFile(path, "w");
        if (f)
        {
            f.WriteLine("# PrimeGate whitelist");
            delete f;
        }
    }

    AutoExecConfig(true, "prime_gate");
}

// ─────────────────────────────────────────────────────────────
// Whitelist helpers
// ─────────────────────────────────────────────────────────────

static void WL_Path(char[] path, int maxlen)
{
    BuildPath(Path_SM, path, maxlen, "configs/prime_whitelist.txt");
}

static void CleanLine(char[] line, int maxlen)
{
    #pragma unused maxlen
    int pos = FindCharInString(line, '#');
    if (pos >= 0) line[pos] = '\0';
    TrimString(line);
}

static void NormalizeSteam2(char[] s2, int maxlen)
{
    #pragma unused maxlen
    if (StrContains(s2, "STEAM_", false) == 0)
    {
        if (s2[6] == '0') s2[6] = '1';
    }
}

static bool LooksLikeSteam64(const char[] s)
{
    int len = strlen(s);
    if (len < 16 || len > 20) return false;
    for (int i = 0; i < len; i++) if (!IsCharNumeric(s[i])) return false;
    return true;
}

static bool LooksLikeSteam2(const char[] s)
{
    return (StrContains(s, "STEAM_", false) == 0);
}

// returns true if entry already present
static bool WL_HasEntry(const char[] entry)
{
    char path[PLATFORM_MAX_PATH];
    WL_Path(path, sizeof(path));
    if (!FileExists(path)) return false;

    File f = OpenFile(path, "r");
    if (!f) return false;

    char line[128];
    bool found = false;

    // Prepare normalized forms for fair compare
    char want64[64], want2[64];
    want64[0] = want2[0] = '\0';

    if (LooksLikeSteam64(entry)) strcopy(want64, sizeof(want64), entry);
    if (LooksLikeSteam2(entry))  { strcopy(want2,  sizeof(want2),  entry); NormalizeSteam2(want2, sizeof(want2)); }

    while (!f.EndOfFile())
    {
        f.ReadLine(line, sizeof(line));
        CleanLine(line, sizeof(line));
        if (line[0] == '\0') continue;

        if (LooksLikeSteam64(line) && want64[0] && StrEqual(line, want64, false)) { found = true; break; }
        if (LooksLikeSteam2(line))
        {
            char file2[64]; strcopy(file2, sizeof(file2), line); NormalizeSteam2(file2, sizeof(file2));
            if (want2[0] && StrEqual(file2, want2, false)) { found = true; break; }
        }
    }
    delete f;
    return found;
}

static bool WL_AddEntryToFile(const char[] entry)
{
    char path[PLATFORM_MAX_PATH];
    WL_Path(path, sizeof(path));

    // Create file if missing
    if (!FileExists(path))
    {
        File nf = OpenFile(path, "w");
        if (!nf) return false;
        nf.WriteLine("# PrimeGate whitelist");
        delete nf;
    }

    // Avoid duplicate
    if (WL_HasEntry(entry)) return true;

    File f = OpenFile(path, "a");
    if (!f) return false;
    f.WriteLine("%s", entry);
    delete f;
    return true;
}

static bool WL_RemoveEntryFromFile(char[] entry)
{
    char path[PLATFORM_MAX_PATH];
    WL_Path(path, sizeof(path));
    if (!FileExists(path)) return false;

    File f = OpenFile(path, "r");
    if (!f) return false;

    char tmp[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, tmp, sizeof(tmp), "configs/prime_whitelist.tmp");

    File out = OpenFile(tmp, "w");
    if (!out) { delete f; return false; }

    char line[128];
    bool removed = false;

    // Prepare normalized targets
    char want64[64], want2[64];
    want64[0] = want2[0] = '\0';
    if (LooksLikeSteam64(entry)) strcopy(want64, sizeof(want64), entry);
    if (LooksLikeSteam2(entry))  { strcopy(want2,  sizeof(want2),  entry); NormalizeSteam2(want2, sizeof(want2)); }

    while (!f.EndOfFile())
    {
        f.ReadLine(line, sizeof(line));
        char raw[128]; 
        strcopy(raw, sizeof(raw), line); // keep original formatting
        CleanLine(line, sizeof(line));

        bool skip = false;
        if (line[0] != '\0')
        {
            if (LooksLikeSteam64(line) && want64[0] && StrEqual(line, want64, false)) skip = true;
            else if (LooksLikeSteam2(line))
            {
                char file2[64]; strcopy(file2, sizeof(file2), line); NormalizeSteam2(file2, sizeof(file2));
                if (want2[0] && StrEqual(file2, want2, false)) skip = true;
            }
        }

        if (skip) { removed = true; continue; }
        out.WriteLine(raw);
    }
    delete f; delete out;

    // Replace original
    DeleteFile(path);
    RenameFile(path, tmp);

    return removed;
}

// Public API: check if a client is in whitelist file (Steam2 or Steam64)
bool IsWhitelisted(int client)
{
    if (!GetConVarBool(gCvarWhitelist)) return false;

    char s64[32], s2[32];
    if (!GetClientAuthId(client, AuthId_SteamID64, s64, sizeof(s64))) s64[0] = '\0';
    if (!GetClientAuthId(client, AuthId_Steam2,   s2,  sizeof(s2)))  s2[0]  = '\0';

    // Fast path: try exact has-entry checks
    if (s64[0] && WL_HasEntry(s64)) return true;

    if (s2[0])
    {
        char s2n[32]; strcopy(s2n, sizeof(s2n), s2); NormalizeSteam2(s2n, sizeof(s2n));
        if (WL_HasEntry(s2n)) return true;

        // If file stored STEAM_0 and we have STEAM_1 (or vice versa), WL_HasEntry handles via normalization.
        // So the above call is sufficient.
    }
    return false;
}

// ─────────────────────────────────────────────────────────────
// Admin / RCON Commands
// ─────────────────────────────────────────────────────────────

public Action Cmd_ReloadWL(int client, int args)
{
    // File is read each time; nothing to reload, just ack for UX.
    ReplyToCommand(client, "[PrimeGate] Whitelist file will be read on next check.");
    return Plugin_Handled;
}

public Action Cmd_WLAdd(int client, int args)
{
    if (args < 1)
    {
        ReplyToCommand(client, "Usage: sm_pwladd <steamid64|steam2>");
        return Plugin_Handled;
    }
    char entry[64];
    GetCmdArg(1, entry, sizeof(entry));
    TrimString(entry);

    if (!LooksLikeSteam64(entry) && !LooksLikeSteam2(entry))
    {
        ReplyToCommand(client, "[PrimeGate] Invalid ID. Provide SteamID64 or STEAM_X:Y:Z");
        return Plugin_Handled;
    }

    // Normalize Steam2 before saving (store as STEAM_1)
    if (LooksLikeSteam2(entry)) NormalizeSteam2(entry, sizeof(entry));

    if (WL_AddEntryToFile(entry))
        ReplyToCommand(client, "[PrimeGate] Added to whitelist: %s", entry);
    else
        ReplyToCommand(client, "[PrimeGate] Failed to add (file error).");

    return Plugin_Handled;
}

public Action Cmd_WLDel(int client, int args)
{
    if (args < 1)
    {
        ReplyToCommand(client, "Usage: sm_prime_wldel <steamid64|steam2>");
        return Plugin_Handled;
    }
    char entry[64];
    GetCmdArg(1, entry, sizeof(entry));
    TrimString(entry);

    if (!LooksLikeSteam64(entry) && !LooksLikeSteam2(entry))
    {
        ReplyToCommand(client, "[PrimeGate] Invalid ID. Provide SteamID64 or STEAM_X:Y:Z");
        return Plugin_Handled;
    }

    // Normalize Steam2 for matching
    if (LooksLikeSteam2(entry)) NormalizeSteam2(entry, sizeof(entry));

    bool ok = WL_RemoveEntryFromFile(entry);
    ReplyToCommand(client, ok ? "[PrimeGate] Removed: %s" : "[PrimeGate] Not found: %s", entry);
    return Plugin_Handled;
}

// ─────────────────────────────────────────────────────────────
// Enforcement
// ─────────────────────────────────────────────────────────────

public void OnClientPutInServer(int client)
{
    if (!GetConVarBool(gCvarEnforce)) return;
    if (!IsClientInGame(client) || IsFakeClient(client)) return;

    // Admin bypass
    if (GetConVarBool(gCvarAllowAdmins) && (GetUserFlagBits(client) & ADMFLAG_GENERIC))
        return;

    // Whitelist bypass
    if (IsWhitelisted(client)) return;

    // Prime check (SteamWorks license)
    EUserHasLicenseForAppResult res = SteamWorks_HasLicenseForApp(client, APPID_CS_PRIME);
    if (res == k_EUserHasLicenseResultHasLicense)
        return;

    // Check if gokz-global is available and query player points
    // First update points, then check after a short delay
    if (GOKZ_GL_GetAPIKeyValid())
    {
        g_bPendingCheck[client] = true;
        // Update points first, then check after a delay
        GOKZ_GL_UpdatePoints(client, -1);
        CreateTimer(1.0, Timer_CheckPlayerPoints, GetClientUserId(client));
        return;
    }

    // Kick if no API available
    int threshold = GetConVarInt(gCvarPointsThreshold);
    char msg[256];
    GetConVarString(gCvarKickMsg, msg, sizeof(msg));
    Format(msg, sizeof(msg), "%s\n\nYou need at least %d points in any GOKZ mode to bypass the Prime requirement.", msg, threshold);
    KickClient(client, "%s", msg);
}

public Action Timer_CheckPlayerPoints(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client == 0 || !IsClientInGame(client))
    {
        if (client > 0 && client <= MaxClients)
        {
            g_bPendingCheck[client] = false;
        }
        return Plugin_Stop;
    }

    if (!g_bPendingCheck[client])
    {
        return Plugin_Stop;
    }

    g_bPendingCheck[client] = false;

    int threshold = GetConVarInt(gCvarPointsThreshold);
    bool hasEnoughPoints = false;
    int maxPoints = 0;

    // Check points in all modes
    for (int mode = 0; mode < MODE_COUNT; mode++)
    {
        int points = GOKZ_GL_GetRankPoints(client, mode);
        if (points > maxPoints)
        {
            maxPoints = points;
        }
        if (points >= threshold)
        {
            hasEnoughPoints = true;
            break;
        }
    }

    // If player has enough points in any mode, allow them to join
    if (hasEnoughPoints)
    {
        return Plugin_Stop;
    }

    // Otherwise, kick them with informative message
    char msg[256];
    GetConVarString(gCvarKickMsg, msg, sizeof(msg));
    Format(msg, sizeof(msg), "%s\n\nYou have %d points (highest across all modes). You need at least %d points in any GOKZ mode to bypass the Prime requirement.", msg, maxPoints, threshold);
    KickClient(client, "%s", msg);
    return Plugin_Stop;
}

public void OnClientDisconnect(int client)
{
    g_bPendingCheck[client] = false;
}
