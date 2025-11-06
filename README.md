# GOKZ Prime Gate

A SourceMod plugin for Counter-Strike 2 servers running GOKZ that enforces Prime account requirements while providing flexible bypass options for trusted players.

## Features

- **Prime Account Enforcement**: Automatically checks if players have CS2 Prime status using SteamWorks
- **Admin Bypass**: Admins with the 'b' flag can bypass Prime requirements
- **Whitelist System**: File-based whitelist for trusted non-Prime players
- **Points Threshold Bypass**: Skilled players with sufficient GOKZ points (configurable) can bypass Prime requirements
- **GOKZ Global Integration**: Automatically checks player points via gokz-global API when available
- **Customizable Messages**: Configurable kick messages with automatic points threshold information

## Requirements

- **SourceMod 1.11+**
- **SteamWorks Extension** (for Prime status checking)
- **GOKZ Core** (for mode enumeration)
- **GOKZ Global** (optional, for points-based bypass)

## Installation

1. Download the latest release from the [Releases](https://github.com/yourusername/prime-gate/releases) page
2. Extract `prime_gate.smx` to `addons/sourcemod/plugins/`
3. Extract `prime_gate.sp` to `addons/sourcemod/scripting/` (optional, for compilation)
4. Restart your server or use `sm plugins reload prime_gate`

The plugin will automatically create `addons/sourcemod/configs/prime_whitelist.txt` on first run.

## Configuration

The plugin creates a config file at `cfg/sourcemod/prime_gate.cfg` with the following ConVars:

### ConVars

| ConVar | Default | Description |
|--------|---------|-------------|
| `sm_prime_enforce` | `1` | Enable/disable Prime enforcement (1 = enabled, 0 = disabled) |
| `sm_prime_allow_admins` | `1` | Allow admins with 'b' flag to bypass (1 = enabled, 0 = disabled) |
| `sm_prime_whitelist` | `1` | Enable file-based whitelist (1 = enabled, 0 = disabled) |
| `sm_prime_kick_message` | `"You need a Prime account to play on this server."` | Custom kick message (points threshold info will be appended automatically) |
| `sm_prime_points_threshold` | `50000` | Minimum points in any GOKZ mode required to bypass Prime requirement |

### Whitelist File

The whitelist file is located at `addons/sourcemod/configs/prime_whitelist.txt`. You can add Steam IDs in two formats:

- **SteamID64**: `76561198012345678`
- **Steam2**: `STEAM_1:0:12345678` or `STEAM_0:0:12345678`

Comments are supported using `#`:

```
# PrimeGate whitelist
# Trusted players
76561198012345678
STEAM_1:0:12345678
```

## Commands

### Admin Commands

| Command | Description | Usage |
|---------|-------------|-------|
| `sm_prime_reload` | Reload whitelist (informational, file is read on each check) | `sm_prime_reload` |
| `sm_padd` / `sm_prime_whitelist_add` | Add a player to the whitelist | `sm_padd <steamid64\|steam2>` |
| `sm_pdel` / `sm_prime_whitelist_del` | Remove a player from the whitelist | `sm_pdel <steamid64\|steam2>` |

**Examples:**
```
sm_padd 76561198012345678
sm_padd STEAM_1:0:12345678
sm_pdel 76561198012345678
```

## How It Works

When a player joins the server, the plugin checks in this order:

1. **Enforcement Check**: If `sm_prime_enforce` is disabled, all players are allowed
2. **Admin Bypass**: If enabled, admins with 'b' flag are allowed
3. **Whitelist Check**: If whitelist is enabled, whitelisted players are allowed
4. **Prime Status Check**: Players with CS2 Prime are allowed
5. **Points Check**: If gokz-global is available, players with enough points (≥ threshold) are allowed
6. **Kick**: If none of the above apply, the player is kicked with a custom message

### Points-Based Bypass

If gokz-global is installed and has a valid API key, the plugin will:
- Update the player's points on join
- Wait 1 second for the API to respond
- Check points across all GOKZ modes
- Allow players with at least `sm_prime_points_threshold` points in any mode

The kick message will include the player's highest points across all modes for transparency.

## Building from Source

If you want to compile the plugin yourself:

1. Ensure you have the SourceMod compiler (`spcomp`) installed
2. Place the required includes in `addons/sourcemod/scripting/include/`:
   - `gokz/core.inc` (from GOKZ)
   - `SteamWorks.inc` (from SteamWorks extension)
3. Compile with:
   ```bash
   spcomp prime_gate.sp
   ```

## License

See [LICENSE](LICENSE) file for details.

## Credits

- **Author**: Cinyan10
- **Website**: https://axekz.com/
- Built for the GOKZ community

## Support

For issues, feature requests, or questions, please open an issue on the GitHub repository.
