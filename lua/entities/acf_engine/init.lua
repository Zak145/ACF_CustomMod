AddCSLuaFile( "shared.lua" )
AddCSLuaFile( "cl_init.lua" )

include('shared.lua')

function ENT:Initialize()

	self.Throttle = 0
	self.Active = false
	self.IsMaster = true
	self.GearLink = {}
	self.GearRope = {}
	self.FuelLink = {}

	self.LastCheck = 0
	self.LastThink = 0
	self.MassRatio = 1
	self.Legal = true
	self.CanUpdate = true
	self.RequiresFuel = false
	
	--####################
	self.TqAdd = 0
	self.MaxRpmAdd = 0
	self.LimitRpmAdd = 0
	self.FlywheelMass = 0
	self.WeightKg = 0
	self.idle = 0
	self.DisableCut = 0
	self.CutMode = 0
	self.CutValue = 0
	self.CutRpm = 0
	self.DisableAutoClutch = 0
	--#####################
	
	self.Inputs = Wire_CreateInputs( self, { "Active", "Throttle", "TqAdd", "MaxRpmAdd", "LimitRpmAdd", "FlywheelMass", "Idle", "DisableCut", "Gearbox RPM"} )
	self.Outputs = WireLib.CreateSpecialOutputs( self, { "RPM", "Torque", "Power", "Fuel Use", "Temperature", "Health", "Entity" , "Mass" , "Physical Mass" }, { "NORMAL" ,"NORMAL", "NORMAL", "NORMAL", "NORMAL" ,"NORMAL" , "ENTITY" , "NORMAL" , "NORMAL" } )
	Wire_TriggerOutput( self, "Entity", self )
	self.WireDebugName = "ACF Engine"

end  

function MakeACF_Engine(Owner, Pos, Angle, Id)

	if not Owner:CheckLimit("_acf_misc") then return false end

	local Engine = ents.Create( "acf_engine" )
	if not IsValid( Engine ) then return false end
	
	local EID
	local List = list.Get("ACFEnts")
	if List["Mobility"][Id] then EID = Id else EID = "5.7-V8" end
	local Lookup = List["Mobility"][EID]
	
	Engine:SetAngles(Angle)
	Engine:SetPos(Pos)
	Engine:Spawn()
	Engine:SetPlayer(Owner)
	Engine.Owner = Owner
	Engine.Id = EID
	
	Engine.Model = Lookup["model"]
	Engine.SoundPath = Lookup["sound"]
	Engine.Weight = Lookup["weight"]
	Engine.PeakTorque = Lookup["torque"]
	Engine.PeakTorqueHeld = Lookup["torque"]
	Engine.IdleRPM = Lookup["idlerpm"]
	Engine.PeakMinRPM = Lookup["peakminrpm"]
	Engine.PeakMaxRPM = Lookup["peakmaxrpm"]
	Engine.LimitRPM = Lookup["limitrpm"]
	Engine.Inertia = Lookup["flywheelmass"]*(3.1416)^2
	Engine.iselec = Lookup["iselec"]
	Engine.elecpower = Lookup["elecpower"]
	Engine.FlywheelOverride = Lookup["flywheeloverride"]
	Engine.IsTrans = Lookup["istrans"] -- driveshaft outputs to the side
	Engine.FuelType = Lookup["fuel"] or "Petrol"
	Engine.EngineType = Lookup["enginetype"] or "GenericPetrol"
	Engine.RequiresFuel = Lookup["requiresfuel"]
	Engine.SpecialHealth = true
	
	--------------------
	Engine.PeakTorque2 = Lookup["torque"]
	Engine.PeakTorque3 = Lookup["torque"]
	Engine.PeakMaxRPM2 = Lookup["peakmaxrpm"]
	Engine.LimitRPM2 = Lookup["limitrpm"]
	Engine.FlywheelMassValue = Lookup["flywheelmass"]
	Engine.FlywheelMass3 = Lookup["flywheelmass"]
	Engine.Idling = Lookup["idlerpm"]
	Engine.CutValue = Engine.LimitRPM / 40
	Engine.CutRpm = Engine.LimitRPM - 100
	Engine.PowerFuelExtra = 1
	--------------------
	--#### Temperature MOD
	Engine.Temp = 0				--Temp at Spawn (Degree)
	Engine.TempMax = Lookup["tempmax"] or 88	--Normal Temp (Degree)
	Engine.TempWarm = 112			--Warm Temp, Engine take dommage if more than it (Degree)
	Engine.TempBlow = 125			--Auto Blow Temp, too high (Degree)
	Engine.EngineHealth = Lookup["enginehealth"] or 100	--Engine Health at Spawn
	Engine.Blowed = 0
	--Getting Rpm High Temp
	Engine.TempRpmHighPercent = Engine.LimitRPM * 0.9 --Getting 90% of the Rpm Band
	if Engine.TempRpmHighPercent <= Engine.PeakMaxRPM then
		Engine.TempRpmHigh = Engine.PeakMaxRPM
	else
		Engine.TempRpmHigh = Engine.LimitRPM * 0.9
	end
	--#####################
	
	--calculate boosted peak kw
	local peakkw
	if Engine.EngineType == "Turbine" or Engine.EngineType == "Electric" then
		peakkw = Engine.PeakTorque * Engine.LimitRPM / (4 * 9548.8)
		Engine.PeakKwRPM = math.floor(Engine.LimitRPM / 2)
	else
		peakkw = Engine.PeakTorque * Engine.PeakMaxRPM / 9548.8
		Engine.PeakKwRPM = Engine.PeakMaxRPM
	end
	
	--calculate base fuel usage
	if Engine.EngineType == "Electric" then
		Engine.FuelUse = ACF.ElecRate / (ACF.Efficiency[Engine.EngineType] * 60 * 60) --elecs use current power output, not max
	else
		Engine.FuelUse = ACF.TorqueBoost * ACF.FuelRate * ACF.Efficiency[Engine.EngineType] * peakkw / (60 * 60)
	end

	Engine.FlyRPM = 0
	Engine:SetModel( Engine.Model )	
	Engine.Sound = nil
	Engine.SoundPitch = 1
	Engine.RPM = {}

	Engine:PhysicsInit( SOLID_VPHYSICS )      	
	Engine:SetMoveType( MOVETYPE_VPHYSICS )     	
	Engine:SetSolid( SOLID_VPHYSICS )

	Engine.Out = Engine:WorldToLocal(Engine:GetAttachment(Engine:LookupAttachment( "driveshaft" )).Pos)

	local phys = Engine:GetPhysicsObject()  	
	if (phys:IsValid()) then 
		phys:SetMass( Engine.Weight ) 
	end

	Engine:SetNetworkedBeamString("Type",Lookup["name"])
	Engine:SetNetworkedBeamInt("Torque",Engine.PeakTorque)	
	Engine:SetNetworkedBeamInt("Power", peakkw)
	Engine:SetNetworkedBeamInt("MinRPM",Engine.PeakMinRPM)
	Engine:SetNetworkedBeamInt("MaxRPM",Engine.PeakMaxRPM)
	Engine:SetNetworkedBeamInt("LimitRPM",Engine.LimitRPM)
	--####################################################
	Engine:SetNetworkedBeamInt("FlywheelMass2",Engine.FlywheelMass3*1000)
	--Engine:SetNetworkedBeamInt("Idle",Engine.IdleRPM)
	--Engine:SetNetworkedBeamInt("Weight",Engine.Weight)
	Engine:SetNetworkedBeamInt("Rpm",Engine.FlyRPM)
	Engine:SetNetworkedBeamInt("Consumption",0)
	Engine:SetNetworkedBeamInt("Temp",Engine.Temp)
	Engine:SetNetworkedBeamInt("Health",Engine.EngineHealth)
	Wire_TriggerOutput(Engine.Entity, "Temperature", Engine.Temp)
	Wire_TriggerOutput(Engine.Entity, "Health", Engine.EngineHealth)
	--####################################################

	Owner:AddCount("_acf_engine", Engine)
	Owner:AddCleanup( "acfmenu", Engine )

	return Engine
end
list.Set( "ACFCvars", "acf_engine" , {"id"} )
duplicator.RegisterEntityClass("acf_engine", MakeACF_Engine, "Pos", "Angle", "Id", "PeakTorque", "IdleRPM", "PeakMinRPM", "PeakMaxRPM", "LimitRPM", "FlywheelMass2")

function ENT:Update( ArgsTable )	--That table is the player data, as sorted in the ACFCvars above, with player who shot, and pos and angle of the tool trace inserted at the start
	-- That table is the player data, as sorted in the ACFCvars above, with player who shot, 
	-- and pos and angle of the tool trace inserted at the start

	if self.Active then
		return false, "Turn off the engine before updating it!"
	end
	
	if ArgsTable[1] ~= self.Owner then -- Argtable[1] is the player that shot the tool
		return false, "You don't own that engine!"
	end

	local Id = ArgsTable[4]	-- Argtable[4] is the engine ID
	local Lookup = list.Get("ACFEnts")["Mobility"][Id]

	if Lookup["model"] ~= self.Model then
		return false, "The new engine must have the same model!"
	end
	
	local Feedback = ""
	if Lookup["fuel"] != self.FuelType then
		Feedback = " Fuel type changed, fuel tanks unlinked."
		for Key,Value in pairs(self.FuelLink) do
			table.remove(self.FuelLink,Key)
			--need to remove from tank master?
		end
	end

	self.Id = Id
	self.SoundPath = Lookup["sound"]
	self.Weight = Lookup["weight"]
	self.PeakTorque = Lookup["torque"]
	self.PeakTorqueHeld = Lookup["torque"]
	self.IdleRPM = Lookup["idlerpm"]
	self.PeakMinRPM = Lookup["peakminrpm"]
	self.PeakMaxRPM = Lookup["peakmaxrpm"]
	self.LimitRPM = Lookup["limitrpm"]
	self.Inertia = Lookup["flywheelmass"]*(3.1416)^2
	self.iselec = Lookup["iselec"] -- is the engine electric?
	self.elecpower = Lookup["elecpower"] -- how much power does it output
	self.FlywheelOverride = Lookup["flywheeloverride"] -- how much power does it output
	self.IsTrans = Lookup["istrans"]
	self.FuelType = Lookup["fuel"]
	self.EngineType = Lookup["enginetype"]
	self.RequiresFuel = Lookup["requiresfuel"]
	self.SpecialHealth = true
	
	---------------------
	self.PeakTorque2 = Lookup["torque"]
	self.PeakTorque3 = Lookup["torque"]
	self.PeakMaxRPM2 = Lookup["peakmaxrpm"]
	self.LimitRPM2 = Lookup["limitrpm"]
	self.FlywheelMassValue = Lookup["flywheelmass"]
	self.FlywheelMass3 = Lookup["flywheelmass"]
	self.Idling = Lookup["idlerpm"]
	self.CutValue = self.LimitRPM / 40
	self.CutRpm = self.LimitRPM - 100
	---------------------
	--#### Temperature MOD
	self.Temp = 0				--Temp at Spawn (Degree)
	self.TempMax = Lookup["tempmax"] or 88	--Normal Temp (Degree)
	self.TempWarm = 112			--Warm Temp, Engine take dommage if more than it (Degree)
	self.TempBlow = 125			--Auto Blow Temp, too high (Degree)
	self.EngineHealth = Lookup["enginehealth"] or 100	--Engine Health at Spawn
	self.Blowed = 0
	--Getting Rpm High Temp
	self.TempRpmHighPercent = 0.9*self.LimitRPM --Getting 90% of the Rpm Band
	if self.TempRpmHighPercent <= self.PeakMaxRPM then
		self.TempRpmHigh = self.PeakMaxRPM
	else
		self.TempRpmHigh = 0.9*self.LimitRPM
	end
	--#####################
	
	--calculate boosted peak kw
	local peakkw
	if self.EngineType == "Turbine" or self.EngineType == "Electric" then
		peakkw = self.PeakTorque * self.LimitRPM / (4 * 9548.8)
		self.PeakKwRPM = math.floor(self.LimitRPM / 2)
	else
		peakkw = self.PeakTorque * self.PeakMaxRPM / 9548.8
		self.PeakKwRPM = self.PeakMaxRPM
	end
	
	--calculate base fuel usage
	if self.EngineType == "Electric" then
		self.FuelUse = ACF.ElecRate / (ACF.Efficiency[self.EngineType] * 60 * 60) --elecs use current power output, not max
	else
		self.FuelUse = ACF.TorqueBoost * ACF.FuelRate * ACF.Efficiency[self.EngineType] * peakkw / (60 * 60)
	end

	self:SetModel( self.Model )	
	self:SetSolid( SOLID_VPHYSICS )
	self.Out = self:WorldToLocal(self:GetAttachment(self:LookupAttachment( "driveshaft" )).Pos)

	local phys = self:GetPhysicsObject()  	
	if IsValid( phys ) then 
		phys:SetMass( self.Weight ) 
	end

	self:SetNetworkedBeamString("Type",Lookup["name"])
	self:SetNetworkedBeamInt("Torque",self.PeakTorque)
	self:SetNetworkedBeamInt("Power",peakkw)
	self:SetNetworkedBeamInt("MinRPM",self.PeakMinRPM)
	self:SetNetworkedBeamInt("MaxRPM",self.PeakMaxRPM)
	self:SetNetworkedBeamInt("LimitRPM",self.LimitRPM)
	--################################################
	self:SetNetworkedBeamInt("FlywheelMass2",self.FlywheelMass3*1000)
	--self:SetNetworkedBeamInt("Idle",self.IdleRPM)
	--self:SetNetworkedBeamInt("Weight",self.Weight)
	self:SetNetworkedBeamInt("Rpm",self.FlyRPM)
	self:SetNetworkedBeamInt("Consumption",0)
	self:SetNetworkedBeamInt("Temp",self.Temp)
	self:SetNetworkedBeamInt("EngineHealth",self.EngineHealth)
	Wire_TriggerOutput(self, "Temperature", self.Temp)
	Wire_TriggerOutput(self, "Health", self.EngineHealth)
	--################################################
	
	ACF_Activate( self, 1 )

	return true, "Engine updated successfully!"
end

function ENT:TriggerInput( iname , value )

	if (iname == "Throttle") then
		self.Throttle = math.Clamp(value,0,100)/100
	elseif (iname == "Active") then
		if (value > 0 and not self.Active) then
			--make sure we have fuel
			local HasFuel
			if not self.RequiresFuel then
				HasFuel = true
			else 
				for _,fueltank in pairs(self.FuelLink) do
					if fueltank.Fuel > 0 and fueltank.Active then HasFuel = true break end
				end
			end
			
			if HasFuel then
				self.RPM = {}
				self.RPM[1] = self.IdleRPM
				self.Active = true
				self.Active2 = true
				self.Sound = CreateSound(self, self.SoundPath)
				self.Sound:PlayEx(0.5,100)
				self:ACFInit()
			end
		elseif (value > 0) then
			local HasFuel
			if not self.RequiresFuel then
				HasFuel = true
			else 
				for _,fueltank in pairs(self.FuelLink) do
					if fueltank.Fuel <= 0 or not fueltank.Active then HasFuel = false break end
				end
			end
			if not HasFuel then
				self:TriggerInput( "Active" , 0 )
				self.Active = false
				Wire_TriggerOutput( self, "RPM", 0 )
				Wire_TriggerOutput( self, "Torque", 0 )
				Wire_TriggerOutput( self, "Power", 0 )
				Wire_TriggerOutput( self, "Fuel Use", 0 )
			end
		elseif (value <= 0 and self.Active) then
			self.Active = false
			Wire_TriggerOutput( self, "RPM", 0 )
			Wire_TriggerOutput( self, "Torque", 0 )
			Wire_TriggerOutput( self, "Power", 0 )
			Wire_TriggerOutput( self, "Fuel Use", 0 )
		end
	--##################################################
	elseif (iname == "TqAdd") then
		if (value ~= 0 ) then
			self.TqAdd = true
			self.PeakTorque3 = self.PeakTorque2+value
			--Reupdating Consumption #############
			local peakkw
			if self.EngineType == "Turbine" or self.EngineType == "Electric" then
				peakkw = self.PeakTorque3 * self.LimitRPM / (4 * 9548.8)
			else
				peakkw = self.PeakTorque3 * self.PeakMaxRPM / 9548.8
			end
			if self.EngineType == "Electric" then else
				self.FuelUse = ACF.TorqueBoost * ACF.FuelRate * ACF.Efficiency[self.EngineType] * peakkw / (60 * 60)
			end
			--####################################
		elseif (value == 0 ) then
			self.TqAdd = false
			self.PeakTorque3 = self.PeakTorque2
			--Reupdating Consumption #############
			local peakkw
			if self.EngineType == "Turbine" or self.EngineType == "Electric" then
				peakkw = self.PeakTorque3 * self.LimitRPM / (4 * 9548.8)
			else
				peakkw = self.PeakTorque3 * self.PeakMaxRPM / 9548.8
			end
			if self.EngineType == "Electric" then else
				self.FuelUse = ACF.TorqueBoost * ACF.FuelRate * ACF.Efficiency[self.EngineType] * peakkw / (60 * 60)
			end
		end
	elseif (iname == "MaxRpmAdd") then
		if (value ~= 0 ) then
			self.MaxRpmAdd = true
			if( self.PeakMaxRPM2+value <= self.LimitRPM ) then
				self.PeakMaxRPM = self.PeakMaxRPM2+value
			elseif( self.PeakMaxRPM2+value > self.LimitRPM ) then
				self.PeakMaxRPM = self.LimitRPM
			end
			self:SetNetworkedBeamInt("MaxRPM",self.PeakMaxRPM)
			--Reupdating Consumption #############
			local peakkw
			if self.EngineType == "Turbine" or self.EngineType == "Electric" then else
				peakkw = self.PeakTorque * self.PeakMaxRPM / 9548.8
				self.PeakKwRPM = self.PeakMaxRPM
			end
			if self.EngineType == "Electric" then else
				self.FuelUse = ACF.TorqueBoost * ACF.FuelRate * ACF.Efficiency[self.EngineType] * peakkw / (60 * 60)
			end
			--Reupdating Temp Mod
			self.TempRpmHighPercent = 0.9*self.LimitRPM --Getting 90% of the Rpm Band
			if self.TempRpmHighPercent <= self.PeakMaxRPM then
				self.TempRpmHigh = self.PeakMaxRPM
			else
				self.TempRpmHigh = 0.9*self.LimitRPM
			end
		elseif (value == 0 ) then
			self.MaxRpmAdd = false
			self.PeakMaxRPM = self.PeakMaxRPM2
			self:SetNetworkedBeamInt("MaxRPM",self.PeakMaxRPM)
			--Reupdating Consumption #############
			local peakkw
			if self.EngineType == "Turbine" or self.EngineType == "Electric" then else
				peakkw = self.PeakTorque * self.PeakMaxRPM / 9548.8
				self.PeakKwRPM = self.PeakMaxRPM
			end
			if self.EngineType == "Electric" then else
				self.FuelUse = ACF.TorqueBoost * ACF.FuelRate * ACF.Efficiency[self.EngineType] * peakkw / (60 * 60)
			end
			--Reupdating Temp Mod
			self.TempRpmHighPercent = 0.9*self.LimitRPM --Getting 90% of the Rpm Band
			if self.TempRpmHighPercent <= self.PeakMaxRPM then
				self.TempRpmHigh = self.PeakMaxRPM
			else
				self.TempRpmHigh = 0.9*self.LimitRPM
			end
		end
	elseif (iname == "LimitRpmAdd") then
		if (value ~= 0 ) then
			self.LimitRpmAdd = true
			self.LimitRPM = self.LimitRPM2+value
			self:SetNetworkedBeamInt("LimitRPM",self.LimitRPM)
			self.CutValue = self.LimitRPM / 40
			self.CutRpm = self.LimitRPM - 100
			--Reupdating Consumption #############
			local peakkw
			if self.EngineType == "Turbine" or self.EngineType == "Electric" then
				peakkw = self.PeakTorque * self.LimitRPM / (4 * 9548.8)
				self.PeakKwRPM = math.floor(self.LimitRPM / 2)
			end
			--Reupdating Temp Mod
			self.TempRpmHighPercent = 0.9*self.LimitRPM --Getting 90% of the Rpm Band
			if self.TempRpmHighPercent <= self.PeakMaxRPM then
				self.TempRpmHigh = self.PeakMaxRPM
			else
				self.TempRpmHigh = 0.9*self.LimitRPM
			end
		elseif (value == 0 ) then
			self.LimitRpmAdd = false
			self.LimitRPM = self.LimitRPM2
			self:SetNetworkedBeamInt("LimitRPM",self.LimitRPM)
			self.CutValue = self.LimitRPM / 40
			self.CutRpm = self.LimitRPM - 100
			--Reupdating Consumption #############
			local peakkw
			if self.EngineType == "Turbine" or self.EngineType == "Electric" then
				peakkw = self.PeakTorque * self.LimitRPM / (4 * 9548.8)
				self.PeakKwRPM = math.floor(self.LimitRPM / 2)
			end
			--Reupdating Temp Mod
			self.TempRpmHighPercent = 0.9*self.LimitRPM --Getting 90% of the Rpm Band
			if self.TempRpmHighPercent <= self.PeakMaxRPM then
				self.TempRpmHigh = self.PeakMaxRPM
			else
				self.TempRpmHigh = 0.9*self.LimitRPM
			end
		end
	elseif (iname == "FlywheelMass") then
		if (value > 0 ) then
			self.FlywheelMass = true
			self.FlywheelMassValue = value
			--self.Inertia = value*(3.1416)^2
			--self:SetNetworkedBeamInt("FlywheelMass2",value*1000)
		elseif (value <= 0 ) then
			self.FlywheelMass = false
			self.FlywheelMassValue = self.FlywheelMass3
			--self.Inertia = self.FlywheelMass3*(3.1416)^2
			--self:SetNetworkedBeamInt("FlywheelMass2",self.FlywheelMass3*1000)
		end
	elseif (iname == "Idle") then
		if (value > 0 ) then
			self.Idle = true
			self.IdleRPM = value
			--self:SetNetworkedBeamInt("Idle",self.IdleRPM)
		elseif (value <= 0 ) then
			self.Idle = false
			self.IdleRPM = self.Idling
			--self:SetNetworkedBeamInt("Idle",self.IdleRPM)
		end
	elseif (iname == "DisableCut") then
		if (value > 0 ) then
			self.DisableCut = 1
		elseif (value <= 0 ) then
			self.DisableCut = 0
		end
	--Disabling AutoClutch on Engine while Moving
	elseif (iname == "Gearbox RPM") then
		if ((value*0.8) > self.IdleRPM and self.Throttle == 0) then
			self.DisableAutoClutch = 1
			self.GearboxRpm = value
		elseif (value <= self.IdleRPM or self.Throttle > 0 and self.DisableAutoClutch == 1) then
			self.DisableAutoClutch = 0
			self.GearboxRpm = 0
		end
	end

end
--######################################################

function ENT:ACF_Activate()
	--Density of steel = 7.8g cm3 so 7.8kg for a 1mx1m plate 1m thick
	local Entity = self
	Entity.ACF = Entity.ACF or {} 
	
	local Count
	local PhysObj = Entity:GetPhysicsObject()
	if PhysObj:GetMesh() then Count = #PhysObj:GetMesh() end
	if PhysObj:IsValid() and Count and Count>100 then

		if not Entity.ACF.Aera then
			Entity.ACF.Aera = (PhysObj:GetSurfaceArea() * 6.45) * 0.52505066107
		end
		--if not Entity.ACF.Volume then
		--	Entity.ACF.Volume = (PhysObj:GetVolume() * 16.38)
		--end
	else
		local Size = Entity.OBBMaxs(Entity) - Entity.OBBMins(Entity)
		if not Entity.ACF.Aera then
			Entity.ACF.Aera = ((Size.x * Size.y)+(Size.x * Size.z)+(Size.y * Size.z)) * 6.45
		end
		--if not Entity.ACF.Volume then
		--	Entity.ACF.Volume = Size.x * Size.y * Size.z * 16.38
		--end
	end
	
	Entity.ACF.Ductility = Entity.ACF.Ductility or 0
	--local Area = (Entity.ACF.Aera+Entity.ACF.Aera*math.Clamp(Entity.ACF.Ductility,-0.8,0.8))
	local Area = (Entity.ACF.Aera)
	--local Armour = (Entity:GetPhysicsObject():GetMass()*1000 / Area / 0.78) / (1 + math.Clamp(Entity.ACF.Ductility, -0.8, 0.8))^(1/2)	--So we get the equivalent thickness of that prop in mm if all it's weight was a steel plate
	local Armour = (Entity:GetPhysicsObject():GetMass()*1000 / Area / 0.78) 
	--local Health = (Area/ACF.Threshold) * (1 + math.Clamp(Entity.ACF.Ductility, -0.8, 0.8))												--Setting the threshold of the prop aera gone
	local Health = (Area/ACF.Threshold)
	
	local Percent = 1 
	
	if Recalc and Entity.ACF.Health and Entity.ACF.MaxHealth then
		Percent = Entity.ACF.Health/Entity.ACF.MaxHealth
	end
	
	Entity.ACF.Health = Health * Percent * ACF.EngineHPMult
	Entity.ACF.MaxHealth = Health * ACF.EngineHPMult
	Entity.ACF.Armour = Armour * (0.5 + Percent/2)
	Entity.ACF.MaxArmour = Armour * ACF.ArmorMod
	Entity.ACF.Type = nil
	Entity.ACF.Mass = PhysObj:GetMass()
	--Entity.ACF.Density = (PhysObj:GetMass()*1000)/Entity.ACF.Volume
	
	Entity.ACF.Type = "Prop"
	--print(Entity.ACF.Health)
end

function ENT:Think()

	local Time = CurTime()

	if self.Active2 then
		if self.Legal then
			self:CalcRPM()
		end

		if self.LastCheck < CurTime() then
			self:CheckRopes()
			self:CheckFuel()
			self:CalcMassRatio()
			if self:GetPhysicsObject():GetMass() < self.Weight or self:GetParent():IsValid() then
				self.Legal = false
			else 
				self.Legal = true
			end

			self.LastCheck = Time + math.Rand(5, 10)
		end
	end

	--#####
	self:SetNetworkedBeamInt("Temp",self.Temp)
	self:SetNetworkedBeamInt("EngineHealth",self.EngineHealth)
	Wire_TriggerOutput(self, "Temperature", self.Temp)
	Wire_TriggerOutput(self, "Health", self.EngineHealth)
	if self.Active == false and self.Temp > 0 then
		self.Temp = self.Temp-0.02
	elseif self.Active == false and self.Temp == 0 then
		self.Temp = 0
	end
	--####
	
	self.LastThink = Time
	self:NextThink( Time )
	return true

end

function ENT:CalcMassRatio()
	
	local Mass = 0
	local PhysMass = 0
	
	-- get the shit that is physically attached to the vehicle
	local PhysEnts = ACF_GetAllPhysicalConstraints( self )
	
	-- add any parented but not constrained props you sneaky bastards
	local AllEnts = table.Copy( PhysEnts )
	for k, v in pairs( PhysEnts ) do
		
		-- gotta make sure the parenting addon is installed...
		if v.GetChildren then table.Merge( AllEnts, v:GetChildren() ) end
		--table.Merge( AllEnts, ACF_GetAllChildren( v ) )
	
	end
	
	for k, v in pairs( AllEnts ) do
		
		if not IsValid( v ) then continue end
		
		local phys = v:GetPhysicsObject()
		if not IsValid( phys ) then continue end
		
		Mass = Mass + phys:GetMass()
		
		if PhysEnts[ v ] then
			PhysMass = PhysMass + phys:GetMass()
		end
		
	end

	self.MassRatio = PhysMass / Mass
	
	Wire_TriggerOutput( self, "Mass", math.Round( Mass, 2 ) )
	Wire_TriggerOutput( self, "Physical Mass", math.Round( PhysMass, 2 ) )
	
end

function ENT:ACFInit()
	
	self:CalcMassRatio()

	self.LastThink = CurTime()
	self.Torque = self.PeakTorque
	self.FlyRPM = self.IdleRPM * 1.5

end

function ENT:CalcRPM()

	local DeltaTime = CurTime() - self.LastThink
	-- local AutoClutch = math.min(math.max(self.FlyRPM-self.IdleRPM,0)/(self.IdleRPM+self.LimitRPM/10),1)
	//local ClutchRatio = math.min(Clutch/math.max(TorqueDiff,0.05),1)
	
	--find first active tank with fuel
	local Tank = nil
	local boost = 1
	for _,fueltank in pairs(self.FuelLink) do
		if fueltank.Fuel > 0 and fueltank.Active then Tank = fueltank break end
		if fueltank.Fuel <= 0 or not fueltank.Active then Tank = false break end
	end
	if (not Tank) and self.RequiresFuel then  --make sure we've got a tank with fuel if needed
		self:TriggerInput( "Active" , 0 )
	end
	if not Tank then
		self:TriggerInput( "Active" , 0 )
	end
	
	--calculate fuel usage
	if Tank then
		local Consumption
		if self.FuelType == "Electric" then
			Consumption = (self.Torque * self.FlyRPM / 9548.8) * self.FuelUse * DeltaTime
		else
			local Load = 0.3 + self.Throttle * 0.7
			Consumption = Load * self.FuelUse * (self.FlyRPM / self.PeakKwRPM) * DeltaTime / ACF.FuelDensity[Tank.FuelType]
		end
		Tank.Fuel = math.max(Tank.Fuel - Consumption,0)
		boost = ACF.TorqueBoost
		Wire_TriggerOutput(self, "Fuel Use", math.Round(60*Consumption/DeltaTime,2))
		self:SetNetworkedBeamInt("Consumption", math.Round((60*Consumption/DeltaTime)*100,2))
	else
		Wire_TriggerOutput(self, "Fuel Use", 0)
		self:SetNetworkedBeamInt("Consumption",0)
	end
	
	--#####################
	--## Temperature Mod ##
	--Set Decreaser and Increaser Value
	local HealthDecreaser = 0.1
	local increaser = 0 --first load
	if self.FlyRPM <= self.TempRpmHigh then
		increaser = 0.04
	elseif self.FlyRPM > self.TempRpmHigh then
		increaser = 0.05
	end
	--## Set Temperature ##
	--increase
	if self.Temp <= (self.TempMax / 2) then
		self.Temp = self.Temp+(increaser*2)
	elseif self.Temp < (self.TempMax - 1) then
		self.Temp = self.Temp+increaser
	--Decrease while safe
	elseif self.Temp > (self.TempMax + 1) and self.FlyRPM <= self.TempRpmHigh then
		self.Temp = self.Temp-increaser
	--Increase while not safe
	elseif self.FlyRPM > self.TempRpmHigh and self.PowerFuelExtra == 0 then
		self.Temp = self.Temp+increaser
	elseif self.FlyRPM > self.TempRpmHigh and self.PowerFuelExtra == 1 then
		self.Temp = self.Temp+(increaser+0.01)
	elseif self.FlyRPM > self.TempRpmHigh and self.PowerFuelExtra == 2 then
		self.Temp = self.Temp+(increaser+0.02)
	elseif self.FlyRPM > self.TempRpmHigh and self.PowerFuelExtra == 3 then
		self.Temp = self.Temp+(increaser+0.03)
	elseif self.FlyRPM > self.TempRpmHigh and self.PowerFuelExtra == 4 then
		self.Temp = self.Temp+(increaser+0.04)
	end
	--Apply Damage if at Dangerous Temp
	if self.Temp > self.TempWarm and self.Temp < self.TempBlow then
		self.EngineHealth = self.EngineHealth-HealthDecreaser
	--Blowing Up
	elseif self.Temp >= self.TempBlow then
		self.EngineHealth = 0
	end
	--Apply Damage at Dangerous RPM without autoclutch
	if self.DisableAutoClutch == 1 and self.FlyRPM > self.LimitRPM then
		self.EngineHealth = self.EngineHealth-HealthDecreaser
	end
	
	if self.EngineHealth <= 0 then
		self.Blowed = 1
		self.Active = false
		self:TriggerInput( "Active" , 0 )
		self:TriggerInput( "Throttle" , 0 )
	end
	
	--Apply Torque Decreaser with Engine Heatlh
	TorqueDecreaser = -(((self.PeakTorque3/2)*(self.EngineHealth-100))/100) --Get Percent with Health
	--####################
	
	-- Calculate the current torque from flywheel RPM
	local TorqueScale = ACF.TorqueScale
	local TorqueMult = 1
	/*if (self.ACF.Health and self.ACF.MaxHealth) then
		TorqueMult = math.Clamp(((1 - TorqueScale) / (0.5)) * ((self.ACF.Health/self.ACF.MaxHealth) - 1) + 1, TorqueScale, 1)
	end*/
	--#### Temperature Mod &&& FUEL Mod FOR TORQUEEEEE
	local PowerFuelAdding
	local FlywheelMassValueAdd
	if self.PowerFuelExtra == 0 then
		PowerFuelAdding = 0
		FlywheelMassValueAdd = 0
	elseif self.PowerFuelExtra == -4 then
		PowerFuelAdding = (self.PeakTorque3*40)/100 -- -40% more power
		FlywheelMassValueAdd = (self.FlywheelMassValue*40)/100 -- +40% adding fly
	elseif self.PowerFuelExtra == -3 then
		PowerFuelAdding = (self.PeakTorque3*30)/100 -- -30% more power
		FlywheelMassValueAdd = (self.FlywheelMassValue*30)/100 -- +30% adding fly
	elseif self.PowerFuelExtra == -2 then
		PowerFuelAdding = (self.PeakTorque3*20)/100 -- -20% more power
		FlywheelMassValueAdd = (self.FlywheelMassValue*20)/100 -- +20% adding fly
	elseif self.PowerFuelExtra == -1 then
		PowerFuelAdding = (self.PeakTorque3*10)/100 -- -10% more power
		FlywheelMassValueAdd = (self.FlywheelMassValue*10)/100 -- +10% adding fly
	elseif self.PowerFuelExtra == 1 then
		PowerFuelAdding = (self.PeakTorque3*10)/100 --10% more power
		FlywheelMassValueAdd = (self.FlywheelMassValue*10)/100 -- -10% adding fly
	elseif self.PowerFuelExtra == 2 then
		PowerFuelAdding = (self.PeakTorque3*15)/100 --20% more power
		FlywheelMassValueAdd = (self.FlywheelMassValue*20)/100 -- -20% adding fly
	elseif self.PowerFuelExtra == 3 then
		PowerFuelAdding = (self.PeakTorque3*25)/100 --30% more power
		FlywheelMassValueAdd = (self.FlywheelMassValue*30)/100 -- -30% adding fly
	elseif self.PowerFuelExtra == 4 then
		PowerFuelAdding = (self.PeakTorque3*35)/100 --40% more power
		FlywheelMassValueAdd = (self.FlywheelMassValue*40)/100 -- -40% adding fly
	end
	local peakkw
	--Apply new value with fuel mod
	if self.PowerFuelExtra >= 0 then
		self.PeakTorque = ((self.PeakTorque3 * TorqueMult)+PowerFuelAdding) - TorqueDecreaser
		self.Inertia = (self.FlywheelMassValue-FlywheelMassValueAdd)*(3.1416)^2
		self:SetNetworkedBeamInt("FlywheelMass2",self.FlywheelMassValue-FlywheelMassValueAdd)
	elseif self.PowerFuelExtra < 0 then
		self.PeakTorque = ((self.PeakTorque3 * TorqueMult)-PowerFuelAdding) - TorqueDecreaser
		self.Inertia = (self.FlywheelMassValue+FlywheelMassValueAdd)*(3.1416)^2
		self:SetNetworkedBeamInt("FlywheelMass2",self.FlywheelMassValue+FlywheelMassValueAdd)
	end
	
	if self.EngineType == "Turbine" or self.EngineType == "Electric" then
		peakkw = self.PeakTorque * self.LimitRPM / (4 * 9548.8)
		self.PeakKwRPM = math.floor(self.LimitRPM / 2)
	else
		peakkw = self.PeakTorque * self.PeakMaxRPM / 9548.8
		self.PeakKwRPM = self.PeakMaxRPM
	end
	self:SetNetworkedBeamInt("Torque",self.PeakTorque)
	self:SetNetworkedBeamInt("Power",peakkw)
	
	--######
	
	local Drag
	local TorqueDiff
	if self.Active then
	if( self.CutMode == 0 ) then
		self.Torque = boost * self.Throttle * math.max( self.PeakTorque * math.min( self.FlyRPM / self.PeakMinRPM , (self.LimitRPM - self.FlyRPM) / (self.LimitRPM - self.PeakMaxRPM), 1 ), 0 )
		
		if self.iselec == true then
			Drag = self.PeakTorque * (math.max( self.FlyRPM - self.IdleRPM, 0) / self.FlywheelOverride) * (1 - self.Throttle) / self.Inertia
		else
			Drag = self.PeakTorque * (math.max( self.FlyRPM - self.IdleRPM, 0) / self.PeakMaxRPM) * ( 1 - self.Throttle) / self.Inertia
		end
	
	elseif( self.CutMode == 1 ) then
		self.Torque = boost * 0 * math.max( self.PeakTorque * math.min( self.FlyRPM / self.PeakMinRPM , (self.LimitRPM - self.FlyRPM) / (self.LimitRPM - self.PeakMaxRPM), 1 ), 0 )
		
		if self.iselec == true then
			Drag = self.PeakTorque * (math.max( self.FlyRPM - self.IdleRPM, 0) / self.FlywheelOverride) * (1 - 0) / self.Inertia
		else
			Drag = self.PeakTorque * (math.max( self.FlyRPM - self.IdleRPM, 0) / self.PeakMaxRPM) * ( 1 - 0) / self.Inertia
		end
		
	end 
	-- Let's accelerate the flywheel based on that torque
	self.FlyRPM = math.max( self.FlyRPM + self.Torque / self.Inertia - Drag, 1 )
	if self.DisableAutoClutch == 0 then
		-- This is the presently avaliable torque from the engine
		TorqueDiff = math.max( self.FlyRPM - self.IdleRPM, 0 ) * self.Inertia
	elseif self.DisableAutoClutch == 1 then
		TorqueDiff = 0
	end

	end
	
	if( self.Active == false ) then
		self.Torque = boost * 0 * math.max( self.PeakTorque * math.min( self.FlyRPM / self.PeakMinRPM , (self.LimitRPM - self.FlyRPM) / (self.LimitRPM - self.PeakMaxRPM), 1 ), 0 )
		if self.iselec == true then
			Drag = self.PeakTorque * (math.max( self.FlyRPM - 0, 0) / self.FlywheelOverride) * (1 - 0) / self.Inertia
		else
			Drag = self.PeakTorque * (math.max( self.FlyRPM - 0, 0) / self.PeakMaxRPM) * ( 1 - 0) / self.Inertia
		end
	
	-- Let's accelerate the flywheel based on that torque
	self.FlyRPM = math.max( self.FlyRPM + self.Torque / self.Inertia - Drag, 1 )
	-- This is the presently avaliable torque from the engine
	TorqueDiff = 0
	
	end
	--##############
	
	-- The gearboxes don't think on their own, it's the engine that calls them, to ensure consistent execution order
	local Boxes = table.Count( self.GearLink )
	
	local MaxTqTable = {}
	local MaxTq = 0
	for Key, Gearbox in pairs(self.GearLink) do
		-- Get the requirements for torque for the gearboxes (Max clutch rating minus any wheels currently spinning faster than the Flywheel)
		MaxTqTable[Key] = Gearbox:Calc( self.FlyRPM, self.Inertia )
		MaxTq = MaxTq + MaxTqTable[Key]
	end
	
	-- Calculate the ratio of total requested torque versus what's avaliable
	local AvailTq = math.min( TorqueDiff / MaxTq / Boxes, 1 )

	for Key, Gearbox in pairs(self.GearLink) do
		-- Split the torque fairly between the gearboxes who need it
		Gearbox:Act( MaxTqTable[Key] * AvailTq * self.MassRatio, DeltaTime )
	end
	
	if self.DisableAutoClutch == 0 then
		self.FlyRPM = self.FlyRPM - (math.min(TorqueDiff,MaxTq)/self.Inertia)
	elseif self.DisableAutoClutch == 1 then
		self.FlyRPM = self.GearboxRpm*0.8
	end
	
	--#######################################
	if( self.DisableCut == 0 ) then
		if( self.FlyRPM >= self.CutRpm and self.CutMode == 0 and self.DisableAutoClutch == 0 ) then
			self.CutMode = 1
			if self.Sound then
				self.Sound:Stop()
			end
			self.Sound = nil
			self.Sound2 = CreateSound(self, "acf_other/penetratingshots/00000293.wav")
			self.Sound2:PlayEx(0.5,100)
		end
		if( self.FlyRPM <= self.CutRpm - self.CutValue and self.CutMode == 1 ) then
			self.CutMode = 0
			self.Sound = CreateSound(self, self.SoundPath)
			self.Sound:PlayEx(0.5,100)
			if self.Sound2 then
				self.Sound2:Stop()
			end
		end
	elseif( self.DisableCut == 1 ) then
		self.CutMode = 0
	end
	if( self.FlyRPM <= 50 and self.Active == false ) then
		self.Active2 = false
		self.FlyRPM = 0
		if self.Sound then
			self.Sound:Stop()
		end
		self.Sound = nil
	end
	--#######################################

	-- Then we calc a smoothed RPM value for the sound effects
	table.remove( self.RPM, 10 )
	table.insert( self.RPM, 1, self.FlyRPM )
	local SmoothRPM = 0
	for Key, RPM in pairs( self.RPM ) do
		SmoothRPM = SmoothRPM + (RPM or 0)
	end
	SmoothRPM = SmoothRPM / 10

	local Power = self.Torque * SmoothRPM / 9548.8
	Wire_TriggerOutput(self, "Torque", math.floor(self.Torque))
	Wire_TriggerOutput(self, "Power", math.floor(Power))
	Wire_TriggerOutput(self, "RPM", self.FlyRPM)
	--##############################################################################################
	self:SetNetworkedBeamInt("Rpm",self.FlyRPM)
	--##############################################################################################
	
	if self.Sound and self.Blowed == 0 then
		self.Sound:ChangePitch( math.min( 20 + (SmoothRPM * self.SoundPitch) / 50, 255 ), 0 )
		self.Sound:ChangeVolume( 0.25 + self.Throttle / 1.5, 0 )
	end
	--Blowed SOUND
	if self.Sound and self.Blowed == 1 then
		self.Sound:ChangePitch( math.min( 20 + (SmoothRPM * self.SoundPitch) / 50, 255 ), 0 )
		self.Sound:ChangeVolume( 0.25 + 1 / 1.5, 0 )
	end
	
	return RPM
end

function ENT:CheckRopes()

	for GearboxKey,Ent in pairs(self.GearLink) do
		local Constraints = constraint.FindConstraints(Ent, "Rope")
		if Constraints then

			local Clean = false
			for Key,Rope in pairs(Constraints) do
				if Rope.Ent1 == self or Rope.Ent2 == self then
					if Rope.length + Rope.addlength < self.GearRope[GearboxKey]*1.5 then
						Clean = true
					end
				end
			end

			if not Clean then
				self:Unlink( Ent )
			end

		else
			self:Unlink( Ent )
		end

		local Direction
		if self.IsTrans then Direction = -self:GetRight() else Direction = self:GetForward() end
		local DrvAngle = (self:LocalToWorld(self.Out) - Ent:LocalToWorld(Ent.In)):GetNormalized():DotProduct((Direction))
		if ( DrvAngle < 0.7 ) then
			self:Unlink( Ent )
		end

	end

end

--unlink fuel tanks out of range
function ENT:CheckFuel()
	for _,tank in pairs(self.FuelLink) do
		if self:GetPos():Distance(tank:GetPos()) > 512 then
			self:Unlink( tank )
			soundstr =  "physics/metal/metal_box_impact_bullet" .. tostring(math.random(1, 3)) .. ".wav"
			self:EmitSound(soundstr,500,100)
		end
	end
end

function ENT:Link( Target )

	if not IsValid( Target ) or Target:GetClass() ~= "acf_gearbox" and Target:GetClass() ~= "acf_gearbox2" and Target:GetClass() ~= "acf_gearbox3" and Target:GetClass() ~= "acf_fueltank" then
		return false, "Can only link to gearboxes!"
	end
	
	if Target:GetClass() == "acf_gearbox" or Target:GetClass() == "acf_gearbox2" or Target:GetClass() == "acf_gearbox3" then
		-- Check if target is already linked
		for Key, Value in pairs( self.GearLink ) do
			if Value == Target then
				return false, "That is already linked to this engine!"
			end
		end

		local InPos = Target:LocalToWorld(Target.In)
		local OutPos = self:LocalToWorld(self.Out)
		local Direction
		if self.IsTrans then Direction = -self:GetRight() else Direction = self:GetForward() end
		local DrvAngle = (OutPos - InPos):GetNormalized():DotProduct((Direction))
		if DrvAngle < 0.7 then
			return false, "Cannot link due to excessive driveshaft angle!"
		end

		table.insert( self.GearLink, Target )
		table.insert( Target.Master, self )
		local RopeL = ( OutPos-InPos ):Length()
		constraint.Rope( self, Target, 0, 0, self.Out, Target.In, RopeL, RopeL * 0.2, 0, 1, "cable/cable2", false )
		table.insert( self.GearRope, RopeL )
	else
		--fuel tank linking
		--######################
		--FUEL MOD
		local AllowableType = false
		--Petrol To Other's
		if self.FuelType == "Petrol" and Target.FuelType == "PlanePetrol" then 
			AllowableType = true
			self.PowerFuelExtra = 4
		elseif self.FuelType == "Petrol" and Target.FuelType == "VP_Racing-112" then 
			AllowableType = true
			self.PowerFuelExtra = 3
		elseif self.FuelType == "Petrol" and Target.FuelType == "Petrol-96" then 
			AllowableType = true
			self.PowerFuelExtra = 2
		elseif self.FuelType == "Petrol" and Target.FuelType == "Petrol-94" then 
			AllowableType = true
			self.PowerFuelExtra = 1
		--Petrol-94 to Other's
		elseif self.FuelType == "Petrol-94" and Target.FuelType == "Petrol" then 
			AllowableType = true
			self.PowerFuelExtra = -1
		elseif self.FuelType == "Petrol-94" and Target.FuelType == "Petrol-96" then 
			AllowableType = true
			self.PowerFuelExtra = 1
		elseif self.FuelType == "Petrol-94" and Target.FuelType == "VP_Racing-112" then 
			AllowableType = true
			self.PowerFuelExtra = 2
		elseif self.FuelType == "Petrol-94" and Target.FuelType == "PlanePetrol" then 
			AllowableType = true
			self.PowerFuelExtra = 3
		--Petrol-96 to Other's
		elseif self.FuelType == "Petrol-96" and Target.FuelType == "Petrol" then 
			AllowableType = true
			self.PowerFuelExtra = -2
		elseif self.FuelType == "Petrol-96" and Target.FuelType == "Petrol-94" then 
			AllowableType = true
			self.PowerFuelExtra = -1
		elseif self.FuelType == "Petrol-96" and Target.FuelType == "VP_Racing-112" then 
			AllowableType = true
			self.PowerFuelExtra = 1
		elseif self.FuelType == "Petrol-96" and Target.FuelType == "PlanePetrol" then 
			AllowableType = true
			self.PowerFuelExtra = 2
		--Plane Petrol to other's
		elseif self.FuelType == "PlanePetrol" and Target.FuelType == "Petrol" then 
			AllowableType = true
			self.PowerFuelExtra = -4
		elseif self.FuelType == "PlanePetrol" and Target.FuelType == "Petrol-94" then 
			AllowableType = true
			self.PowerFuelExtra = -3
		elseif self.FuelType == "PlanePetrol" and Target.FuelType == "Petrol-96" then 
			AllowableType = true
			self.PowerFuelExtra = -2
		elseif self.FuelType == "PlanePetrol" and Target.FuelType == "VP_Racing-112" then 
			AllowableType = true
			self.PowerFuelExtra = -1
		end
		if not (self.FuelType == "Any" and not (Target.FuelType == "Electric")) then
			if not (self.FuelType == Target.FuelType or AllowableType == true) then
				return false, "Cannot link because fuel type is incompatible."
			end
		end
		--#######################
		
		if Target.NoLinks then
			return false, "This fuel tank doesn\'t allow linking."
		end
		
		local Duplicate = false
		for Key,Value in pairs(self.FuelLink) do
			if Value == Target then Duplicate = true break end
		end
		
		if not Duplicate then
			if self:GetPos():Distance(Target:GetPos()) < 512 then
				table.insert(self.FuelLink,Target)
				table.insert(Target.Master,self)
			else
				return false, "Fuel tank is too far away."
			end
		else
			return false, "That is already linked to this engine!"
		end
	end
	
	return true, "Link successful!"
end

function ENT:Unlink( Target )

	local Success = false
	
	if Target:GetClass() == "acf_gearbox" or Target:GetClass() == "acf_gearbox2" or Target:GetClass() == "acf_gearbox3" then
		for Key,Value in pairs(self.GearLink) do
			if Value == Target then

				local Constraints = constraint.FindConstraints(Value, "Rope")
				if Constraints then
					for Key,Rope in pairs(Constraints) do
						if Rope.Ent1 == self or Rope.Ent2 == self then
							Rope.Constraint:Remove()
						end
					end
				end

				table.remove(self.GearLink,Key)
				table.remove(self.GearRope,Key)
				Success = true
			end
		end
	else
		for Key,Value in pairs(self.FuelLink) do
			if Value == Target then
				table.remove(self.FuelLink,Key)
				--need to remove from tank master?
				Success = true
			end
		end
	end
		
	if Success then
		return true, "Unlink successful!"
	else
		return false, "That is not linked to this engine!"
	end

end

function ENT:PreEntityCopy()

	//Link Saving
	local info = {}
	local entids = {}
	for Key, Value in pairs(self.GearLink) do					--First clean the table of any invalid entities
		if not Value:IsValid() then
			table.remove(self.GearLink, Value)
		end
	end
	for Key, Value in pairs(self.GearLink) do					--Then save it
		table.insert(entids, Value:EntIndex())
	end

	info.entities = entids
	if info.entities then
		duplicator.StoreEntityModifier( self, "GearLink", info )
	end
	
	--fuel tank link saving
	local fuel_info = {}
	local fuel_entids = {}
	for Key, Value in pairs(self.FuelLink) do					--First clean the table of any invalid entities
		if not Value:IsValid() then
			table.remove(self.FuelLink, Value)
		end
	end
	for Key, Value in pairs(self.FuelLink) do					--Then save it
		table.insert(fuel_entids, Value:EntIndex())
	end
	
	fuel_info.entities = fuel_entids
	if fuel_info.entities then
		duplicator.StoreEntityModifier( self, "FuelLink", fuel_info )
	end

	//Wire dupe info
	local DupeInfo = WireLib.BuildDupeInfo( self )
	if DupeInfo then
		duplicator.StoreEntityModifier( self, "WireDupeInfo", DupeInfo )
	end

end

function ENT:PostEntityPaste( Player, Ent, CreatedEntities )

	//Link Pasting
	if (Ent.EntityMods) and (Ent.EntityMods.GearLink) and (Ent.EntityMods.GearLink.entities) then
		local GearLink = Ent.EntityMods.GearLink
		if GearLink.entities and table.Count(GearLink.entities) > 0 then
			for _,ID in pairs(GearLink.entities) do
				local Linked = CreatedEntities[ ID ]
				if Linked and Linked:IsValid() then
					self:Link( Linked )
				end
			end
		end
		Ent.EntityMods.GearLink = nil
	end

	--fuel tank link Pasting
	if (Ent.EntityMods) and (Ent.EntityMods.FuelLink) and (Ent.EntityMods.FuelLink.entities) then
		local FuelLink = Ent.EntityMods.FuelLink
		if FuelLink.entities and table.Count(FuelLink.entities) > 0 then
			for _,ID in pairs(FuelLink.entities) do
				local Linked = CreatedEntities[ ID ]
				if Linked and Linked:IsValid() then
					self:Link( Linked )
				end
			end
		end
		Ent.EntityMods.FuelLink = nil
	end

	//Wire dupe info
	if(Ent.EntityMods and Ent.EntityMods.WireDupeInfo) then
		WireLib.ApplyDupeInfo(Player, Ent, Ent.EntityMods.WireDupeInfo, function(id) return CreatedEntities[id] end)
	end

end

function ENT:OnRemove()
	if self.Sound then
		self.Sound:Stop()
	end
	Wire_Remove( self )
end

function ENT:OnRestore()
	Wire_Restored( self )
end