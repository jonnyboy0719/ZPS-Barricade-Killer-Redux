/**
 * Gets the owner of the entity
 */
stock GetEntityOwner(entity)
{
	return GetEntProp(entity, Prop_Send, "m_hOwnerEntity");
}

/**
 * Sets the owner of the entity
 */
stock SetEntityOwner(entity, client)
{
	SetEntProp(entity, Prop_Send, "m_hOwnerEntity", client);
}

/**
 * Gets the entity team
 */
stock GetEntityTeam(entity)
{
	return GetEntProp(entity, Prop_Send, "m_iTeamNum");
}

/**
 * Gets the entity team
 */
stock SetEntityTeam(entity, team)
{
	SetEntProp(entity, Prop_Send, "m_iTeamNum", team);
}