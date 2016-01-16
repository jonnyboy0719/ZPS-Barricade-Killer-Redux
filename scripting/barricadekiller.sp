#pragma semicolon 1

#define PLUGIN_VERSION "1.2"
#define PLUGIN_NAME "ZPS Barricade Killer (Redux)"

#define MAX_LINE_WIDTH 64

#include <sourcemod>
#include <sdktools>
#include <health>
#include <zps_entity>
// Don't have colors include file? get it here: http://forums.alliedmods.net/showthread.php?t=96831 (This version only works on 2007 Engine)
#include <colors>

/*ChangeLog
1.0		Release
1.1		Added Blacklist system
1.2		Added 'Punishment timer'
*/

// Temp fix for server crashing if no team were found
#define NULL		0
#define NULL2		1

// Define the teams
#define SURVIVOR	2
#define ZOMBIE		3
#define READY		4

public Plugin:myinfo =
{
	name = PLUGIN_NAME,
	author = "JonnyBoy0719",
	description = "Notification when a Survivor Kills a Barricade.",
	version = PLUGIN_VERSION,
	url = "http://jonnyboy0719.co.uk/"
}

//Cvars
new Handle:hEnabled = INVALID_HANDLE,
	Handle:hPunish = INVALID_HANDLE,
	Handle:hPunishscale = INVALID_HANDLE,
	Handle:hPunishmultiply = INVALID_HANDLE,
	Handle:hPunishTotal = INVALID_HANDLE,
	Handle:hPunishOwner = INVALID_HANDLE,
	Handle:hReset = INVALID_HANDLE,
	Handle:hDebug = INVALID_HANDLE,
	Handle:hPTimer = INVALID_HANDLE,
	Handle:hLan = INVALID_HANDLE;

//Blacklisted
new bool:ClientIsBlacklisted[MAXPLAYERS+1];

//Player Vars
new cadeKillCount[MAXPLAYERS+1] = {0, ...},
	CadeTimer[MAXPLAYERS+1] = {0, ...};

public OnPluginStart()
{
	//Cvars
	CreateConVar("zps_barricadekiller_version", PLUGIN_VERSION, "ZPS Barricade Killer Version.", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	hEnabled = CreateConVar("sm_barricadekiller_enabled", "1", "Turns Barricade Killer Off/On. (1/0)", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	hPunish = CreateConVar("sm_barricadekiller_punish", "0", "Punish the person who broke it, 0=disabled, 1=enabled.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	hPunishscale = CreateConVar("sm_barricadekiller_punish_scale", "1", "Set the slap damage, 1=min, 99=max.", FCVAR_PLUGIN, true, 1.0, true, 99.0);
	hPunishmultiply = CreateConVar("sm_barricadekiller_punish_multiply", "2", "Set the slap damage multiplier, 1=min, 99=max.", FCVAR_PLUGIN, true, 0.0, true, 99.0);
	hPunishTotal = CreateConVar("sm_barricadekiller_punish_total", "5", "How many times they need to break a barricade until punishment takes effect, 1=min, 15=max.", FCVAR_PLUGIN, true, 1.0, true, 15.0);
	hPunishOwner = CreateConVar("sm_barricadekiller_punish_owner", "1", "Don't punish the owner, 0=disabled, 1=enabled.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	hPTimer = CreateConVar("sm_barricadekiller_punish_timer", "60", "How many seconds until it won't punish the player if they break it. 0=disabled.", FCVAR_PLUGIN, true, 0.0, true, 160.0);
	hReset = CreateConVar("sm_barricadekiller_reset", "2", "When to reset Running Totals, 0=never, 1=map, 2=round.", FCVAR_PLUGIN, true, 0.0, true, 2.0);
	hDebug = CreateConVar("sm_barricadekiller_debug", "0", "Debugging mode, 0=disabled, 1=enabled.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	
	//Commands
	RegAdminCmd ("sm_blacklist", Command_BlackList, ADMFLAG_BAN);
	RegAdminCmd ("sm_bl", Command_BlackList, ADMFLAG_BAN);

	//Hooks
	HookEvent("break_prop", SomethingBroke);
	HookEvent("player_spawn", PlayerSpawned);
	HookEvent("game_round_restart", RoundRestart);

	// Check if LAN is enabled
	hLan = FindConVar("sv_lan");
	if (GetConVarInt(hLan))
		LogMessage("ATTENTION! %s in LAN environment is based on IP address rather than Steam ID.", PLUGIN_NAME);

	//Translations
	LoadTranslations("barricadekiller.phrases");

	// Lets create a config file
	AutoExecConfig(true, "zps_barricadekiller");
}

/*
	OnMapEnd()
*/
public OnMapEnd()
{
	if (GetConVarBool(hEnabled) && GetConVarInt(hReset) == 1)
	{
		for (new i = 1; i < MaxClients; i++)
		{
			if(IsClientInGame(i) && !IsFakeClient(i))
			{
				cadeKillCount[i] = 0;
			}
		}
	}
}

/*
	Action:PlayerSpawned()
*/
public Action:PlayerSpawned(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!GetConVarBool(hEnabled))
		return;

	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	ReadBlackList(client);
	
	CadeTimer[client] = 0;
}

/*
	Action:Command_BlackList()
*/
public Action:Command_BlackList( client, args )
{
	if (!GetConVarBool(hEnabled))
		return Plugin_Handled;

	if (args < 1)
	{
		ReplyToCommand(client, "[Barricade Killer] Usage: blacklist <#userid|name>");
		return Plugin_Handled;
	}

	decl String:arg[65];
	GetCmdArg(1, arg, sizeof(arg) );

	decl String:target_name[MAX_TARGET_LENGTH];
	decl target_list[MAXPLAYERS], target_count, bool:tn_is_ml;

	if ((target_count = ProcessTargetString(
		arg,
		client,
		target_list,
		MAXPLAYERS,
		0,
		target_name,
		sizeof(target_name),
		tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}

	for (new i = 0; i < target_count; i++)
	{
		PerformBlacklist(client, target_list[i]);
	}

	return Plugin_Continue;
}

/*
	Action:ReadBlackList()
*/
public Action:ReadBlackList(client)
{
	if (!ValidatePlayer(client))
		return;

	// Gets the SteamID for the target player
	decl String:SteamID[MAX_LINE_WIDTH];
	GetClientAuthString_R(client, SteamID, sizeof(SteamID));

	decl String:path[PLATFORM_MAX_PATH],String:current_line[128];
	BuildPath(Path_SM, path, PLATFORM_MAX_PATH,"configs/zps_barricadekiller_blacklist.cfg");

	// Opens addons/sourcemod/configs/zps_barricadekiller_blacklist.cfg
	new Handle:fileHandle = OpenFile(path,"r");

	while(!IsEndOfFile(fileHandle) && ReadFileLine(fileHandle, current_line, sizeof(current_line)))
	{
		if(StrContains(current_line, SteamID, false) == 0)
		{
			ClientIsBlacklisted[client] = true;
			CPrintToChat(client, "[{green}Barricade Killer{default}] {blue}You are blacklisted");
		}
	}

	CloseHandle(fileHandle);
}

/*
	Action:RoundRestart()
*/
public Action:RoundRestart(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (GetConVarBool(hEnabled) && GetConVarInt(hReset) == 2)
	{
		for (new i = 1; i < MaxClients; i++)
		{
			if(IsClientInGame(i) && !IsFakeClient(i))
			{
				cadeKillCount[i] = 0;
			}
		}
	}
}

/*
	Action:OnPlayerRunCmd()
*/
public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
	if (!GetConVarBool(hEnabled))
		return;

	if (ClientIsBlacklisted[client])
		return;

	if ((buttons & IN_ATTACK) == IN_ATTACK) 
	{
		// Lets grab the weapon classname
		new String:classname[64];
		GetClientWeapon(client, classname, 64);

		// Lets make sure its a barricade model
		if(StrEqual(classname, "weapon_barricade"))
		{
			CreateTimer(0.81, SetBarricadeOwner, client);
		}
	}
}

/*
	Action:SetBarricadeOwner()
*/
public Action:SetBarricadeOwner(Handle:timer, any:client)
{
	if (!ValidatePlayer(client))
		return Plugin_Stop;

	// Lets grab the entity
	new ent = GetClientAimTarget(client, false);

	if (ent == -1)
		return Plugin_Stop;

	// Now, lets grab its model
	decl String:model[128];
	GetEntPropString(ent, Prop_Data, "m_ModelName", model, sizeof(model));

	// If someone already own this barricade, don't override it!
	if (GetEntityOwner(ent) != -1)
		return Plugin_Stop;

	// Lets make sure its a barricade model
	if (StrContains(model, "/barricades/", false) != -1)
	{
		// Lets set the owner
		SetEntityOwner(ent, client);
		CPrintToChat(client, "[{green}Barricade Killer{default}] {blue}Owner ID set");
		// Lets set the timer
		if (GetConVarInt(hPTimer) > 0)
		{
			CadeTimer[client] = 0;
			CreateTimer(1.0, SetTimer, client, TIMER_REPEAT);
		}
	}

	return Plugin_Stop;
}

/*
	Action:SetTimer()
*/
public Action:SetTimer(Handle:timer, any:client)
{
	if (!ValidatePlayer(client))
		return Plugin_Stop;
	
	if (CadeTimer[client] < GetConVarInt(hPTimer))
		CadeTimer[client]++;
	else
	{
		CadeTimer[client] = 0;
		return Plugin_Stop;
	}
	
	return Plugin_Handled;
}

/*
	Action:SomethingBroke()
*/
public Action:SomethingBroke(Handle:event, const String:name[], bool:dontBroadcast)
{	
	if (!GetConVarBool(hEnabled))
		return;

	// The client who broke it
	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!ValidatePlayer(client))
		return;

	new team = GetClientTeam(client);
	
	// Server will crash if there is no team.
	if (team == SURVIVOR)
	{
		new ent = GetEventInt(event, "entindex");

		// If it somehow don't find the entity, lets just kill it here
		if (ent == -1)
			return;

		// if nobody own the board, don't punish or anything
		if (GetEntityOwner(ent) == -1)
			return;

		decl String:model[128];
		GetEntPropString(ent, Prop_Data, "m_ModelName", model, sizeof(model));
		
		if (StrContains(model, "/barricades/", false) != -1)
		{
			if (GetConVarBool(hPunishOwner))
			{
				// DEBUG
				if (GetConVarBool(hDebug))
					CPrintToChat(client, "{green}Debug{default}: {blue}Client ID: %i | Owner ID: %i", client, GetEntityOwner(ent));
				if (GetEntityOwner(ent) == client)
					return;
			}

			cadeKillCount[client]++;
			
			new String:killerName[MAX_NAME_LENGTH];
			GetClientName(client, killerName, sizeof(killerName));
			
			new total = cadeKillCount[client],
				grab_cades_time = CadeTimer[client],
				total_goal = GetConVarInt(hPunishTotal),
				flags;
			
			for (new i = 1; i < MaxClients; i++)
			{
				if(IsClientInGame(i) && !IsFakeClient(i))
				{
					// Get the flags
					flags = GetUserFlagBits(i);

					if (GetConVarBool(hPunish))
					{
						// If timer is set, and cade timer is the same as the timer.
						if (GetConVarInt(hPTimer) > 0 && grab_cades_time >= GetConVarInt(hPTimer))
							return;
						// If the total is more, or equals to the total_goal, call this
						if (total >= total_goal)
						{
							// Now, lets get more serious
							DamagePlayer(client, GetConVarInt(hPunishscale)+total*GetConVarInt(hPunishmultiply)*GetConVarInt(hPunishTotal));
							// DEBUG
							if (GetConVarBool(hDebug))
								CPrintToChat(i, "{green}Debug{default}: {blue}%i+%i*%i*%i", GetConVarInt(hPunishscale), total, GetConVarInt(hPunishmultiply), GetConVarInt(hPunishTotal));
						}
						else
						{
							DamagePlayer(client, GetConVarInt(hPunishscale)+total*GetConVarInt(hPunishmultiply));
							// DEBUG
							if (GetConVarBool(hDebug))
								CPrintToChat(i, "{green}Debug{default}: {blue}%i+%i*%i", GetConVarInt(hPunishscale), total, GetConVarInt(hPunishmultiply));
						}
					}
				
					if (i == client)
					{
						if (GetConVarBool(hPunish))
						{
							CPrintToChat(i, "[{green}Barricade Killer{default}] {olive}%t", "You_Punish");
						}
						else
						{
							CPrintToChat(i, "[{green}Barricade Killer{default}] {olive}%t", "You");
						}
					}
					else
					{
						
						if (flags & ADMFLAG_ROOT || flags & ADMFLAG_GENERIC)
						{
							if (GetConVarBool(hPunish))
							{
								CPrintToChat(i, "[{green}Barricade Killer{default}] {olive}%t", "Admin_Punish", killerName, total);
							}
							else
							{
								CPrintToChat(i, "[{green}Barricade Killer{default}] {olive}%t", "Admin", killerName, total);
							}
						}
						else if (GetClientTeam(i))
						{
							if (GetConVarBool(hPunish))
							{
								CPrintToChat(i, "[{green}Barricade Killer{default}] {olive}%t", "All_Punish", killerName);
							}
							else
							{
								CPrintToChat(i, "[{green}Barricade Killer{default}] {olive}%t", "All", killerName);
							}
						}
					}
				}
			}
			
			LogMessage("%L Broke a Barricade! (total: %i)", client, total);
		}
	}
	else
		return;
}

/*
	DamagePlayer()
*/
DamagePlayer(client, damage)
{
	new min = 1;
	new max = 4;
	new rand = GetRandomInt(min,max);

	decl String:wavefile[512];

	Format(wavefile, sizeof(wavefile), "Impacts/FallHard-0%i.wav", rand);

	new health = GetClientHealth(client);
	new new_health = health - damage;

	if (new_health <= 0)
		ForcePlayerSuicide(client);
	else
		SetClientHealth(client, new_health);
	EmitSoundToClient(client, wavefile);
}

/*
	ValidatePlayer
*/
ValidatePlayer(client)
{
	// Sorry server, but you are not welcome here!
	if (client == 0)
		return false;

	// Checks if the player is in-game, connected and not a bot
	if(!IsClientInGame(client)
		|| IsFakeClient(client)
		|| !IsClientConnected(client))
		return false;

	return true;
}

/*
	OnBlacklistExist()
*/
OnBlacklistExist(client)
{
	decl String:path[PLATFORM_MAX_PATH],String:current_line[128];
	BuildPath(Path_SM,path,PLATFORM_MAX_PATH,"configs/zps_barricadekiller_blacklist.cfg");

	// Gets the SteamID for the target player
	decl String:SteamID[MAX_LINE_WIDTH];
	GetClientAuthString_R(client, SteamID, sizeof(SteamID));

	// Opens addons/sourcemod/configs/zps_barricadekiller_blacklist.cfg
	new Handle:fileHandle=OpenFile(path,"r");

	while(!IsEndOfFile(fileHandle) && ReadFileLine(fileHandle, current_line, sizeof(current_line)))
	{
		if(StrContains(current_line, SteamID, false) == 0)
		{
			return true;
		}
	}

	CloseHandle(fileHandle);

	return false;
}

/*
	PerformBlacklist()
*/
stock PerformBlacklist(client, target)
{
	if (!ValidatePlayer(client) || !ValidatePlayer(target))
		return;

	// Gets the SteamID for the target player
	decl String:SteamID[MAX_LINE_WIDTH];
	GetClientAuthString_R(target, SteamID, sizeof(SteamID));

	if (OnBlacklistExist(target))
	{
		// Player already exists
		CPrintToChat(client, "[{green}Barricade Killer{default}] {blue}The SteamID {default}\"{green}%s{default}\"{blue} already exist on the blacklist!", SteamID);
		return;
	}

	LogAction(client, target, "\"%L\" added \"%L\" to the blacklist.", client, target);
	//---------------------------------
	decl String:path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, PLATFORM_MAX_PATH, "configs/zps_barricadekiller_blacklist.cfg");

	// Opens addons/sourcemod/configs/zps_barricadekiller_blacklist.cfg
	new Handle:fileHandle = OpenFile(path, "a");

	// Writes the line
	WriteFileLine(fileHandle, SteamID);

	CloseHandle(fileHandle);
	//---------------------------------

	// Tell the admin its done
	CPrintToChat(client, "[{green}Barricade Killer{default}] {blue}You have succefully added {default}\"{green}%s{default}\"{blue} to the blacklist", SteamID);

	ClientIsBlacklisted[client] = true;
}

/*
	GetClientRankAuthString()
*/
GetClientAuthString_R(client, String:auth[], maxlength)
{
	if (GetConVarInt(hLan))
	{
		GetClientAuthString(client, auth, maxlength);

		if (!StrEqual(auth, "BOT", false))
		{
			GetClientIP(client, auth, maxlength);
		}
	}
	else
	{
		GetClientAuthString(client, auth, maxlength);

		if (StrEqual(auth, "STEAM_ID_LAN", false))
		{
			GetClientIP(client, auth, maxlength);
		}
	}
}