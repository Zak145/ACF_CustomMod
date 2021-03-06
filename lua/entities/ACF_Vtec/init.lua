AddCSLuaFile( "shared.lua" )
AddCSLuaFile( "cl_init.lua" )

include('shared.lua')

function ENT:Initialize()

	--input
	self.RPM = false

	
	self.CanUpdate = true
	
	self.Inputs = Wire_CreateInputs( self, { "RPM" } )
	self.Outputs = WireLib.CreateSpecialOutputs( self, { "ActiveChips" }, { "NORMAL" } )
	Wire_TriggerOutput(self, "Entity", self)
	self.WireDebugName = "ACF Vtec"

end  

function MakeACF_Vtec(Owner, Pos, Angle, Id, Data1)

	if not Owner:CheckLimit("_acf_misc") then return false end
	
	local Vtec = ents.Create("acf_vtec")
	local List = list.Get("ACFEnts")
	local Classes = list.Get("ACFClasses")
	if not Vtec:IsValid() then return false end
	Vtec:SetAngles(Angle)
	Vtec:SetPos(Pos)
	Vtec:Spawn()
	
	Vtec:SetPlayer(Owner)
	Vtec.Owner = Owner
	Vtec.Id = Id
	Vtec.Model = List["Mobility"][Id]["model"]
	Vtec.Weight = List["Mobility"][Id]["weight"]
	Vtec.ModTable = List["Mobility"][Id]["modtable"]
		Vtec.ModTable[1] = Data1
		Vtec.KickRpm = Data1
	
	Vtec.KickActive = 0
	Vtec.Kickv = tonumber(Vtec.KickRpm)
	
	Vtec:SetModel( Vtec.Model )
	
	Vtec:PhysicsInit( SOLID_VPHYSICS )      	
	Vtec:SetMoveType( MOVETYPE_VPHYSICS )     	
	Vtec:SetSolid( SOLID_VPHYSICS )
	
	local phys = Vtec:GetPhysicsObject()  	
	if (phys:IsValid()) then 
		phys:SetMass( Vtec.Weight ) 
	end
	
	Vtec:SetNetworkedBeamString("Type",List["Mobility"][Id]["name"])
	Vtec:SetNetworkedBeamInt("Kicking",Vtec.KickRpm)
	Vtec:SetNetworkedBeamInt("Weight",Vtec.Weight)
	
	Owner:AddCount("_acf_vtec", Vtec)
	Owner:AddCleanup( "acfmenu", Vtec )
	
	return Vtec
end

list.Set( "ACFCvars", "acf_vtec" , {"id", "data1"} )
duplicator.RegisterEntityClass("acf_vtec", MakeACF_Vtec, "Pos", "Angle", "Id", "KickRpm")


--if updating
function ENT:Update( ArgsTable )	--That table is the player data, as sorted in the ACFCvars above, with player who shot, and pos and angle of the tool trace inserted at the start
	-- That table is the player data, as sorted in the ACFCvars above, with player who shot, 
	-- and pos and angle of the tool trace inserted at the start

	if ArgsTable[1] ~= self.Owner then -- Argtable[1] is the player that shot the tool
		return false, "You don't own that vtec!"
	end

	local Id = ArgsTable[4]	-- Argtable[4] is the engine ID
	local List = list.Get("ACFEnts")

	if List["Mobility"][Id]["model"] ~= self.Model then
		return false, "The new vtec must have the same model!"
	end
	
	if self.Id != Id then
		self.Id = Id
		self.Model = List["Mobility"][Id]["model"]
		self.Weight = List["Mobility"][Id]["weight"]
		self.KickActive = 0
	end
	
	self.ModTable[1] = ArgsTable[5]
	self.KickRpm = ArgsTable[5]
	self.Kickv = tonumber(self.KickRpm)
	
	self:SetNetworkedBeamString("Type",List["Mobility"][Id]["name"])
	self:SetNetworkedBeamInt("Kicking",self.KickRpm)
	self:SetNetworkedBeamInt("Weight",self.Weight)
	
	
	return true, "Vtec updated successfully!"
end

function ENT:TriggerInput( iname , value )
	if (iname == "RPM") then
		if (value > self.Kickv) then
			self.RPM = true
			self.KickActive = 1
			Wire_TriggerOutput(self, "ActiveChips", self.KickActive)
		elseif (value <= self.Kickv) then
			self.RPM = false
			self.KickActive = 0
			Wire_TriggerOutput(self, "ActiveChips", self.KickActive)
		end
	end

end

function ENT:PreEntityCopy()
	//Wire dupe info
	local DupeInfo = WireLib.BuildDupeInfo( self )
	if DupeInfo then
		duplicator.StoreEntityModifier( self, "WireDupeInfo", DupeInfo )
	end

end

function ENT:PostEntityPaste( Player, Ent, CreatedEntities )
	//Wire dupe info
	if(Ent.EntityMods and Ent.EntityMods.WireDupeInfo) then
		WireLib.ApplyDupeInfo(Player, Ent, Ent.EntityMods.WireDupeInfo, function(id) return CreatedEntities[id] end)
	end
end

function ENT:OnRemove()
	Wire_Remove(self)
end

function ENT:OnRestore()
    Wire_Restored(self)
end
	