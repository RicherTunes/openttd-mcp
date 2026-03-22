# OpenTTD MCP Setup

Perform the full setup sequence to get OpenTTD connected and ready to play.

## Steps

1. **Install GameScript**: Use `install_gamescript` to copy ClaudeMCP to the OpenTTD game scripts directory.
2. **Configure OpenTTD**: Use `setup_openttd` to set admin_password in openttd.cfg.
3. **Launch OpenTTD**: Use `launch_openttd` with the path `D:\Alex\PetProjects\OpenTTD-vanilla\build\Release\openttd.exe`.
4. **Wait for user** to start a game with ClaudeMCP GameScript selected, then start a multiplayer server.
5. **Connect**: Use `connect_to_server` with password "claude".
6. **Verify**: Run `get_towns` to confirm the GameScript is working.

## Important Notes

- The bridge server auto-starts with the MCP. No separate terminal needed.
- OpenTTD must be restarted to pick up GameScript changes.
- The admin port (3977) only opens AFTER the server is started AND admin_password was set BEFORE OpenTTD launched.
- For vanilla OpenTTD builds, set `allow_insecure_admin_login = true` in openttd.cfg if connection fails, then use `setting network.admin_password claude` in the console and `restart`.
- GameScript commands are serialized (one at a time) to prevent game freezes.
