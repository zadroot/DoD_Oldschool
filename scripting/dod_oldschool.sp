#include <sdkhooks>

#define PLUGIN_NAME    "DoD:S Oldschool"
#define PLUGIN_VERSION "1.0"
#define CLASS_INIT     0
#define MAX_CLASS      6

#define m_iDesiredPlayerClass(%1) (GetEntProp(%1, Prop_Send, "m_iDesiredPlayerClass"))

enum Teams
{
	TEAM_UNASSIGNED,
	TEAM_SPECTATOR,
	TEAM_ALLIES,
	TEAM_AXIS,
	TEAM_SIZE
};

enum HitGroups
{
	generic,
	head,
	body,
	chest,
	left_arm,
	right_arm,
	left_leg,
	right_leg
};

static const String:block_cmds[][] = { "cls_random", "joinclass" },
	String:allies_cmds[][]  = { "cls_garand", "cls_tommy", "cls_bar",  "cls_spring", "cls_30cal", "cls_bazooka"  },
	String:axis_cmds[][]    = { "cls_k98",    "cls_mp40",  "cls_mp44", "cls_k98s",   "cls_mg42",  "cls_pschreck" },
	String:allies_cvars[][] =
{
	"mp_limit_allies_rifleman",
	"mp_limit_allies_assault",
	"mp_limit_allies_support",
	"mp_limit_allies_sniper",
	"mp_limit_allies_mg",
	"mp_limit_allies_rocket"
},
	String:axis_cvars[][] =
{
	"mp_limit_axis_rifleman",
	"mp_limit_axis_assault",
	"mp_limit_axis_support",
	"mp_limit_axis_sniper",
	"mp_limit_axis_mg",
	"mp_limit_axis_rocket"
};

new	classlimit[TEAM_SIZE][MAX_CLASS],
	Handle:dod_friendlyfiresafezone,
	Handle:dod_freezecam,
	Handle:mp_rocketdamage,
	Handle:mp_rocketradius,
	m_bPlayerDominatingMe,
	m_bPlayerDominated;

public Plugin:myinfo =
{
	name        = PLUGIN_NAME,
	author      = "dodsplugins.com developers team",
	description = "Enables old features (no freezecam, collision, etc) which was available before \"palermo update\"",
	version     = PLUGIN_VERSION,
	url         = "http://dodsplugins.com/"
};


public OnPluginStart()
{
	if ((m_bPlayerDominatingMe = FindSendPropInfo("CDODPlayer", "m_bPlayerDominatingMe")) == -1)
	{
		SetFailState("Unable to find prop offset: \"m_bPlayerDominatingMe\"!");
	}

	if ((m_bPlayerDominated = FindSendPropInfo("CDODPlayer", "m_bPlayerDominated")) == -1)
	{
		SetFailState("Unable to find prop offset: \"m_bPlayerDominated\"!");
	}

	CreateConVar("dod_oldschool_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_NOTIFY|FCVAR_DONTRECORD);

	for (new i; i < sizeof(block_cmds); i++)
	{
		AddCommandListener(OtherClass, block_cmds[i]);
	}

	for (new i; i < MAX_CLASS; i++)
	{
		AddCommandListener(OnAlliesClass, allies_cmds[i]);
		AddCommandListener(OnAxisClass,   axis_cmds[i]);

		classlimit[TEAM_ALLIES][i] = GetConVarInt(FindConVar(allies_cvars[i]));
		classlimit[TEAM_AXIS][i]   = GetConVarInt(FindConVar(axis_cvars[i]));

		HookConVarChange(FindConVar(allies_cvars[i]), UpdateClassLimits);
		HookConVarChange(FindConVar(axis_cvars[i]),   UpdateClassLimits);
	}

	dod_friendlyfiresafezone = FindConVar("dod_friendlyfiresafezone");
	dod_freezecam = FindConVar("dod_freezecam");

	decl ConVarFlags;

	mp_rocketdamage = FindConVar("mp_rocketdamage");
	if (mp_rocketdamage != INVALID_HANDLE)
	{
		ConVarFlags = GetConVarFlags(mp_rocketdamage);
		ConVarFlags &= ~FCVAR_CHEAT;

		SetConVarFlags(mp_rocketdamage, ConVarFlags);
	}

	mp_rocketradius = FindConVar("mp_rocketradius");
	if (mp_rocketradius != INVALID_HANDLE)
	{
		ConVarFlags = GetConVarFlags(mp_rocketradius);
		ConVarFlags &= ~FCVAR_CHEAT;

		SetConVarFlags(mp_rocketradius, ConVarFlags);
	}

	HookEvent("player_death", OnPlayerDeath_Pre, EventHookMode_Pre);
}

public UpdateClassLimits(Handle:convar, const String:oldValue[], const String:newValue[])
{
	for (new i; i < MAX_CLASS; i++)
	{
		classlimit[TEAM_ALLIES][i] = GetConVarInt(FindConVar(allies_cvars[i]));
		classlimit[TEAM_AXIS][i]   = GetConVarInt(FindConVar(axis_cvars[i]));
	}
}

public OnConfigsExecuted()
{
	SetConVarBool(dod_friendlyfiresafezone, false);
	SetConVarBool(dod_freezecam, false);

	SetConVarInt(mp_rocketdamage, 210);
	SetConVarInt(mp_rocketradius, 160);
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_TraceAttack,   OnTraceAttack);
	SDKHook(client, SDKHook_ShouldCollide, OnShouldCollide);
}

public Action:OnTraceAttack(victim, &attacker, &inflictor, &Float:damage, &damagetype, &ammotype, hitbox, hitgroup)
{
	if (1 <= attacker <= MaxClients)
	{
		if (hitgroup > 3)
		{
			damage *= 1.34;
		}

		return Plugin_Changed;
	}

	return Plugin_Continue;
}

public Action:OnPlayerDeath_Pre(Handle:event, String:name[], bool:dontBroadcast)
{
	if (GetEventBool(event, "dominated")
	|| GetEventBool(event, "revenge"))
	{
		SetEventBool(event, "dominated", false);
		SetEventBool(event, "revenge",   false);
		ResetDominations(GetClientOfUserId(GetEventInt(event, "attacker")), GetClientOfUserId(GetEventInt(event, "userid")));
	}
}

public Action:OnAlliesClass(client, const String:command[], argc)
{
	new team = GetClientTeam(client);

	if (IsPlayerAlive(client) && Teams:team == Teams:TEAM_ALLIES)
	{
		new class = CLASS_INIT;
		new cvar  = CLASS_INIT;

		for (new i = CLASS_INIT; i < sizeof(allies_cmds); i++)
		{
			if (StrEqual(command, allies_cmds[i]))
			{
				class = cvar = i;
				break;
			}
		}

		if (IsClassAvailable(client, team, class, cvar))
		{
			PrintUserMessage(client, class, command);
			SetEntProp(client, Prop_Send, "m_iDesiredPlayerClass", class);
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public Action:OnAxisClass(client, const String:command[], argc)
{
	new team = GetClientTeam(client);

	if (IsPlayerAlive(client) && Teams:team == Teams:TEAM_AXIS)
	{
		new class = CLASS_INIT;
		new cvar  = CLASS_INIT;

		for (new i = CLASS_INIT; i < sizeof(axis_cmds); i++)
		{
			if (StrEqual(command, axis_cmds[i]))
			{
				class = cvar = i;
				break;
			}
		}

		if (IsClassAvailable(client, team, class, cvar))
		{
			PrintUserMessage(client, class, command);
			SetEntProp(client, Prop_Send, "m_iDesiredPlayerClass", class);
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public Action:OtherClass(client, const String:command[], argc)
{
	return Plugin_Handled;
}

public bool:OnShouldCollide(client, collisionGroup, contentsMask, bool:originalResult)
{
	return true;
}

bool:IsClassAvailable(client, team, desiredclass, cvarnumber)
{
	new class = CLASS_INIT;

	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == team)
		{
			if (m_iDesiredPlayerClass(i) == desiredclass) class++;
		}
	}

	if ((class >= classlimit[team][cvarnumber])
	&& (classlimit[team][cvarnumber] > -1)
	|| (m_iDesiredPlayerClass(client)) == desiredclass)
	{
		return false;
	}

	return true;
}

ResetDominations(attacker, victim)
{
	SetEntData(victim, m_bPlayerDominatingMe + attacker, false, true, true);
	SetEntData(attacker,  m_bPlayerDominated + victim,   false, true, true);
}

PrintUserMessage(client, desiredclass, const String:command[])
{
	if (m_iDesiredPlayerClass(client) != desiredclass)
	{
		new Handle:TextMsg = StartMessageOne("TextMsg", client);

		if (TextMsg != INVALID_HANDLE)
		{
			decl String:buffer[128];
			Format(buffer, sizeof(buffer), "\x03#Game_respawn_as");
			BfWriteString(TextMsg, buffer);
			Format(buffer, sizeof(buffer), "#%s", command);
			BfWriteString(TextMsg, buffer);
			EndMessage();
		}
	}
}