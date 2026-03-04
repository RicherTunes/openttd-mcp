/**
 * ClaudeMCP GameScript - Metadata
 * This GameScript receives JSON commands from the MCP server via the admin port
 * and executes in-game actions (building, vehicles, queries).
 */

class ClaudeMCPInfo extends GSInfo {
  function GetAuthor()      { return "Claude MCP"; }
  function GetName()        { return "ClaudeMCP"; }
  function GetDescription() { return "GameScript bridge for Claude MCP server. Receives JSON commands via admin port and executes in-game actions."; }
  function GetVersion()     { return 3; }
  function GetDate()        { return "2025-01-01"; }
  function CreateInstance()  { return "ClaudeMCP"; }
  function GetShortName()   { return "CMCP"; }
  function GetAPIVersion()  { return "15"; }
  function GetURL()         { return ""; }

  function GetSettings() {
    AddSetting({
      name = "log_level",
      description = "Logging level (0=off, 1=errors, 2=info, 3=debug)",
      min_value = 0,
      max_value = 3,
      default_value = 2,
      flags = 0
    });
  }
}

RegisterGS(ClaudeMCPInfo());
