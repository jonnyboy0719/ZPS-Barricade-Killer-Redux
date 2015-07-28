#pragma semicolon 1
#define PLUGIN_VERSION "1.0"
#include <sourcemod>
#include <sdktools>
#include <health>
#include <zps_entity>
// Don't have colors include file? get it here: http://forums.alliedmods.net/showthread.php?t=96831 (This version only works on 2007 Engine)
#include <colors>

/*ChangeLog
1.0		Release
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
	name = "ZPS Barricade Killer (Redux)",
	author = "JonnyBoy0719",
	description = "Notification when a Survivor Kills a Barricade.",
	version = PLUGIN_VERSION,
	url = "not_yet_available"
}

//Cvars
new Handle:hEnabled = INVALID_HANDLE;
new Handle:hPunish = INVALID_HANDLE;
new Handle:hPunishscale = INVALID_HANDLE;
new Handle:hPunishmultiply = INVALID_HANDLE;
new Handle:hPunishTotal = INVALID_HANDLE;
new Handle:hPunishOwner = INVALID_HANDLE;
new Handle:hReset = INVALID_HANDLE;
new Handle:hDebug = INVALID_HANDLE;

//Player Vars
new cadeKillCount[MAXPLAYERS+1] = {0, ...};

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
	hReset = CreateConVar("sm_barricadekiller_reset", "2", "When to reset Running Totals, 0=never, 1=map, 2=round.", FCVAR_PLUGIN, true, 0.0, true, 2.0);
	hDebug = CreateConVar("sm_barricadekiller_debug", "0", "Debugging mode, 0=disabled, 1=enabled.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	
	//Hooks
	HookEvent("break_prop", SomethingBroke);
	HookEvent("game_round_restart", RoundRestart);
	
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
		CPrintToChat(client, "[{green}Barricade Killer{default}] {red}Owner ID set");
	}

	return Plugin_Stop;
}

/*
	Action:SomethingBroke()
*/
public Action:SomethingBroke(Handle:event, const String:name[], bool:dontBroadcast)
{	
	if (!GetConVarBool(hEnabled))
	{
		return;
	}

	// The client who broke it
	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!ValidatePlayer(client))
		return;

	new team = GetClientTeam(client);
	
	// Server will crash if there is no team.
	if (team == SURVIVOR)
	{
		new ent = GetEventInt(event, "entindex");

		decl String:model[128];
		GetEntPropString(ent, Prop_Data, "m_ModelName", model, sizeof(model));
		
		if (StrContains(model, "/barricades/", false) != -1)
		{
			if (GetConVarBool(hPunishOwner))
			{
				// DEBUG
				if (GetConVarBool(hDebug))
					CPrintToChat(client, "{green}Debug{default}: {red}Client ID: %i | Owner ID: %i", client, GetEntityOwner(ent));
				if (GetEntityOwner(ent) == client)
					return;
			}

			cadeKillCount[client]++;
			
			new String:killerName[MAX_NAME_LENGTH];
			GetClientName(client, killerName, sizeof(killerName));
			
			new total = cadeKillCount[client];
			new total_goal = GetConVarInt(hPunishTotal);
			new flags;
			
			for (new i = 1; i < MaxClients; i++)
			{
				if(IsClientInGame(i) && !IsFakeClient(i))
				{
					// Get the flags
					flags = GetUserFlagBits(i);

					if (GetConVarBool(hPunish))
					{
						// If the total is more, or equals to the total_goal, call this
						if (total >= total_goal)
						{
							// Now, lets get more serious
							DamagePlayer(client, GetConVarInt(hPunishscale)+total*GetConVarInt(hPunishmultiply)*GetConVarInt(hPunishTotal));
							// DEBUG
							if (GetConVarBool(hDebug))
								CPrintToChat(i, "{green}Debug{default}: {red}%i+%i*%i*%i", GetConVarInt(hPunishscale), total, GetConVarInt(hPunishmultiply), GetConVarInt(hPunishTotal));
						}
						else
						{
							DamagePlayer(client, GetConVarInt(hPunishscale)+total*GetConVarInt(hPunishmultiply));
							// DEBUG
							if (GetConVarBool(hDebug))
								CPrintToChat(i, "{green}Debug{default}: {red}%i+%i*%i", GetConVarInt(hPunishscale), total, GetConVarInt(hPunishmultiply));
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