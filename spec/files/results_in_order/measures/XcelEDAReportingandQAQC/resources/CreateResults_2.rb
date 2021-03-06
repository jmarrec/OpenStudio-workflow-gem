#start the measure
class XcelEDAReportingandQAQC < OpenStudio::Ruleset::ReportingUserScript
  def create_results()  

    # get the current version of OS being used to determine if sql query
    # changes are needed (for when E+ changes).
    os_version = OpenStudio::VersionString.new(OpenStudio::openStudioVersion())
    
    #create an attribute vector to hold results
    result_elems = {}
    
    #floor_area
    floor_area_query = "SELECT Value FROM tabulardatawithstrings WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' AND ReportForString='Entire Facility' AND TableName='Building Area' AND RowName='Net Conditioned Building Area' AND ColumnName='Area' AND Units='m2'" 
    floor_area = @sql.execAndReturnFirstDouble(floor_area_query)
    if floor_area.is_initialized
      @runner.registerValue("charsfloor_area", floor_area.get, "m^2")
    else
      @runner.registerWarning("Building floor area not found")
      return false
    end
    
    #inflation approach
    inf_appr_query = "SELECT Value FROM tabulardatawithstrings WHERE ReportName='Life-Cycle Cost Report' AND ReportForString='Entire Facility' AND TableName='Life-Cycle Cost Parameters' AND RowName='Inflation Approach' AND ColumnName='Value'" 
    inf_appr = @sql.execAndReturnFirstString(inf_appr_query)
    if inf_appr.is_initialized
      if inf_appr.get == "ConstantDollar"
        inf_appr = "Constant Dollar"
      elsif inf_appr.get == "CurrentDollar"
        inf_appr = "Current Dollar"
      else
        @runner.registerError("Inflation approach: #{inf_appr.get} not recognized")
        return false
      end
      @runner.registerInfo("Inflation approach = #{inf_appr}")
    else
      @runner.registerError("Could not determine inflation approach used")
      return false
    end

    #base year
    base_yr_query = "SELECT Value FROM tabulardatawithstrings WHERE ReportName='Life-Cycle Cost Report' AND ReportForString='Entire Facility' AND TableName='Life-Cycle Cost Parameters' AND RowName='Base Date' AND ColumnName='Value'"
    base_yr = @sql.execAndReturnFirstString(base_yr_query)
    if base_yr.is_initialized
      if base_yr.get.match(/\d\d\d\d/)
        base_yr = base_yr.get.match(/\d\d\d\d/)[0].to_f
      else
        @runner.registerError("Could not determine the analysis start year from #{base_yr.get}")
        return false
      end
    else
      @runner.registerError("Could not determine analysis start year")
      return false      
    end
    
    #analysis length
    length_yrs_query = "SELECT Value FROM tabulardatawithstrings WHERE ReportName='Life-Cycle Cost Report' AND ReportForString='Entire Facility' AND TableName='Life-Cycle Cost Parameters' AND RowName='Length of Study Period in Years' AND ColumnName='Value'" 
    length_yrs = @sql.execAndReturnFirstInt(length_yrs_query)
    if length_yrs.is_initialized
      @runner.registerInfo"Analysis length = #{length_yrs.get} yrs"
      length_yrs = length_yrs.get
    else
      @runner.registerError("Could not determine analysis length")
      return false      
    end    
    
    #cash flow types
    @runner.registerValue("cash_flows_capital_type", "#{inf_appr} Capital Costs")
    @runner.registerValue("cash_flows_operating_type", "#{inf_appr} Operating Costs")
    @runner.registerValue("cash_flows_energy_type", "#{inf_appr} Energy Costs")
    @runner.registerValue("cash_flows_water_type", "#{inf_appr} Water Costs")
    @runner.registerValue("cash_flows_total_type", "#{inf_appr} Total Costs")   
    
    #loop through each year and record the cash flow by year
    for i in 0..(length_yrs - 1) do
      new_yr = base_yr + i
      
      yr = nil
      if os_version > OpenStudio::VersionString.new("1.5.3")
        yr = "January         #{new_yr.round}"
      else
        yr = "January           #{new_yr.round}"
      end
      
      ann_cap_cash = 0.0
      ann_om_cash = 0.0
      ann_energy_cash = 0.0
      ann_water_cash = 0.0
      ann_tot_cash = 0.0
    
      #capital cash flow
      cap_cash_query = "SELECT Value FROM tabulardatawithstrings WHERE ReportName='Life-Cycle Cost Report' AND ReportForString='Entire Facility' AND TableName='Capital Cash Flow by Category (Without Escalation)' AND RowName='#{yr}' AND ColumnName='Total'"
      cap_cash = @sql.execAndReturnFirstDouble(cap_cash_query)
      if cap_cash.is_initialized
        ann_cap_cash += cap_cash.get
        ann_tot_cash += cap_cash.get
      end
  
      #o&m cash flow (excluding utility costs)
      om_types = ["Maintenance", "Repair","Operation", "Replacement", "MinorOverhaul", "MajorOverhaul", "OtherOperational"] 
      om_types.each do |om_type|
        om_cash_query = "SELECT Value FROM tabulardatawithstrings WHERE ReportName='Life-Cycle Cost Report' AND ReportForString='Entire Facility' AND TableName='Operating Cash Flow by Category (Without Escalation)' AND RowName='#{yr}' AND ColumnName='#{om_type}'"
        om_cash = @sql.execAndReturnFirstDouble(om_cash_query)
        if om_cash.is_initialized
          ann_om_cash += om_cash.get
          ann_tot_cash += om_cash.get
        end
      end
  
      #energy cash flow
      energy_cash_query = "SELECT Value FROM tabulardatawithstrings WHERE ReportName='Life-Cycle Cost Report' AND ReportForString='Entire Facility' AND TableName='Operating Cash Flow by Category (Without Escalation)' AND RowName='#{yr}' AND ColumnName='Energy'"
      energy_cash = @sql.execAndReturnFirstDouble(energy_cash_query)
      if energy_cash.is_initialized
        ann_energy_cash += energy_cash.get
        ann_tot_cash += energy_cash.get
      end  
  
      #water cash flow
      water_cash_query = "SELECT Value FROM tabulardatawithstrings WHERE ReportName='Life-Cycle Cost Report' AND ReportForString='Entire Facility' AND TableName='Operating Cash Flow by Category (Without Escalation)' AND RowName='#{yr}' AND ColumnName='Water'"
      water_cash = @sql.execAndReturnFirstDouble(water_cash_query)
      if water_cash.is_initialized
        ann_water_cash += water_cash.get
        ann_tot_cash += water_cash.get
      end 

      #log the values for this year
      @runner.registerValue("cash_flows_capital_year_#{i + 1}", ann_cap_cash, "dollars")
      @runner.registerValue("cash_flows_operating_year_#{i + 1}", ann_om_cash, "dollars")
      @runner.registerValue("cash_flows_energy_year_#{i + 1}", ann_energy_cash, "dollars")
      @runner.registerValue("cash_flows_water_year_#{i + 1}", ann_water_cash, "dollars")
      @runner.registerValue("cash_flows_total_year_#{i + 1}", ann_tot_cash, "dollars")
   
    end #next year

    #end cash flows
    
    #list of all end uses in OpenStudio
    end_use_cat_types = []
    OpenStudio::EndUseCategoryType::getValues.each do |end_use_val|
      end_use_cat_types << OpenStudio::EndUseCategoryType.new(end_use_val)
    end

    #list of all end use fuel types in OpenStudio
    end_use_fuel_types = []
    OpenStudio::EndUseFuelType::getValues.each do |end_use_fuel_type_val|
      end_use_fuel_types << OpenStudio::EndUseFuelType.new(end_use_fuel_type_val)
    end  
      
    #list of the 12 months of the year in OpenStudio
    months = []
    OpenStudio::MonthOfYear::getValues.each do |month_of_year_val|
      if month_of_year_val >= 1 and month_of_year_val <= 12
        months << OpenStudio::MonthOfYear.new(month_of_year_val)
      end
    end
    
    #map each end use category type to the name that will be used in the xml 
    end_use_map = {
      OpenStudio::EndUseCategoryType.new("Heating").value => "heating",
      OpenStudio::EndUseCategoryType.new("Cooling").value => "cooling",
      OpenStudio::EndUseCategoryType.new("InteriorLights").value => "lighting_interior",
      OpenStudio::EndUseCategoryType.new("ExteriorLights").value => "lighting_exterior",
      OpenStudio::EndUseCategoryType.new("InteriorEquipment").value => "equipment_interior",
      OpenStudio::EndUseCategoryType.new("ExteriorEquipment").value => "equipment_exterior",
      OpenStudio::EndUseCategoryType.new("Fans").value => "fans",
      OpenStudio::EndUseCategoryType.new("Pumps").value => "pumps",
      OpenStudio::EndUseCategoryType.new("HeatRejection").value => "heat_rejection",
      OpenStudio::EndUseCategoryType.new("Humidifier").value => "humidification",
      OpenStudio::EndUseCategoryType.new("HeatRecovery").value => "heat_recovery",
      OpenStudio::EndUseCategoryType.new("WaterSystems").value => "water_systems",
      OpenStudio::EndUseCategoryType.new("Refrigeration").value => "refrigeration",
      OpenStudio::EndUseCategoryType.new("Generators").value => "generators"
    }
      
    #map each fuel type in EndUseFuelTypes to a specific FuelTypes
    fuel_type_map = {  
      OpenStudio::EndUseFuelType.new("Electricity").value => OpenStudio::FuelType.new("Electricity"),
      OpenStudio::EndUseFuelType.new("Gas").value => OpenStudio::FuelType.new("Gas"),
      OpenStudio::EndUseFuelType.new("AdditionalFuel").value => OpenStudio::FuelType.new("Diesel"), #TODO add other fuel types
      OpenStudio::EndUseFuelType.new("DistrictCooling").value => OpenStudio::FuelType.new("DistrictCooling"),
      OpenStudio::EndUseFuelType.new("DistrictHeating").value => OpenStudio::FuelType.new("DistrictHeating"),
      OpenStudio::EndUseFuelType.new("Water").value => OpenStudio::FuelType.new("Water")
    }  

    #map each fuel type in EndUseFuelTypes to a specific FuelTypes
    fuel_type_alias_map = {  
      OpenStudio::EndUseFuelType.new("Electricity").value => "electricity",
      OpenStudio::EndUseFuelType.new("Gas").value => "gas",
      OpenStudio::EndUseFuelType.new("AdditionalFuel").value => "other_energy",
      OpenStudio::EndUseFuelType.new("DistrictCooling").value => "district_cooling",
      OpenStudio::EndUseFuelType.new("DistrictHeating").value => "district_heating",
      OpenStudio::EndUseFuelType.new("Water").value => "water"
    }

    #annual "annual"

      #consumption "consumption"

        #electricity
        electricity = @sql.electricityTotalEndUses
        if electricity.is_initialized
          @runner.registerValue("annual_consumption_electricity", electricity.get, "GJ")
        else
          @runner.registerValue("annual_consumption_electricity", 0.0, "GJ")
        end      
      
        #gas
        gas = @sql.naturalGasTotalEndUses
        if gas.is_initialized
          @runner.registerValue("annual_consumption_gas", gas.get, "GJ")
        else
          @runner.registerValue("annual_consumption_gas", 0.0, "GJ")
        end       

        #other_energy
        other_energy = @sql.otherFuelTotalEndUses
        if other_energy.is_initialized
          @runner.registerValue("annual_consumption_other_energy", other_energy.get, "GJ")
        else
          @runner.registerValue("annual_consumption_other_energy", 0.0, "GJ")
        end

        #district_cooling
        district_cooling = @sql.districtCoolingTotalEndUses
        if district_cooling.is_initialized
          @runner.registerValue("annual_consumption_district_cooling", district_cooling.get, "GJ")
        else
          @runner.registerValue("annual_consumption_district_cooling", 0.0, "GJ")
        end
        
        #district_heating
        district_heating = @sql.districtHeatingTotalEndUses
        if district_heating.is_initialized
          @runner.registerValue("annual_consumption_district_heating", district_heating.get, "GJ")
        else
          @runner.registerValue("annual_consumption_district_heating", 0.0, "GJ")
        end
        
        #water
        water = @sql.waterTotalEndUses
        if water.is_initialized
          @runner.registerValue("annual_consumption_water", water.get, "m^3")
        else
          @runner.registerValue("annual_consumption_water", 0.0, "m^3")
        end
        
      #end consumption

      #demand "demand"

        #get the weather file run period (as opposed to design day run period)
        ann_env_pd = nil
        @sql.availableEnvPeriods.each do |env_pd|
          env_type = @sql.environmentType(env_pd)
          if env_type.is_initialized
            if env_type.get == OpenStudio::EnvironmentType.new("WeatherRunPeriod")
              ann_env_pd = env_pd
            end
          end
        end
      
        #only try to get the annual peak demand if an annual simulation was run
        if ann_env_pd
        
          #create some units to use
          joule_unit = OpenStudio::createUnit("J").get
          gigajoule_unit = OpenStudio::createUnit("GJ").get
          hrs_unit = OpenStudio::createUnit("h").get
          kilowatt_unit = OpenStudio::createUnit("kW").get
      
          #get the annual hours simulated
          hrs_sim = "(0 - no partial annual simulation)"
          if @sql.hoursSimulated.is_initialized
            hrs_sim = @sql.hoursSimulated.get
            if hrs_sim != 8760
              @runner.registerError("Simulation was only #{hrs_sim} hrs; EDA requires an annual simulation (8760 hrs)")
              return false
            end
          end
      
          # Setup the Xcel peak demand time window
          # in the months of June thru September
          # between 2 pm and 6 pm
          # Per Jen Elling on 8.7.2014, it is ok NOT TO EXCLUDE weekends
          # and holidays. Excluding them is currently difficult because 
          # of an OS bug, and she did not think it was worth the effort to fix.
          # This will only impact corner-case buildings that have
          # peak demand on weekends or holidays, which is unusual.
          june_first = OpenStudio::DateTime.new(OpenStudio::Date.new(OpenStudio::MonthOfYear.new("June"), 1), OpenStudio::Time.new(0, 0, 0, 0))
          sept_thirtieth = OpenStudio::DateTime.new(OpenStudio::Date.new(OpenStudio::MonthOfYear.new("September"), 30), OpenStudio::Time.new(0, 24, 0, 0))
          two_pm = OpenStudio::Time.new(0, 14, 0, 0)
          six_pm = OpenStudio::Time.new(0, 18, 0, 0)
          
          #electricity_peak_demand
          electricity_peak_demand = -1.0
          electricity_peak_demand_time = nil
          elec = @sql.timeSeries(ann_env_pd, "Zone Timestep", "Electricity:Facility", "")
          #deduce the timestep based on the hours simulated and the number of datapoints in the timeseries
          if elec.is_initialized
            elec = elec.get            
            num_int = elec.values.size
            int_len_hrs = OpenStudio::Quantity.new(hrs_sim/num_int, hrs_unit)
            
            # Put timeseries into array
            elec_vals = []
            ann_elec_vals = elec.values
            for i in 0..(ann_elec_vals.size - 1)
              elec_vals << ann_elec_vals[i]
            end            
 
            # Put values into array
            elec_times = []
            ann_elec_times = elec.dateTimes
            for i in 0..(ann_elec_times.size - 1)
              elec_times << ann_elec_times[i]
            end
                        
            # Loop through the time/value pairs and find the peak
            # excluding the times outside of the Xcel peak demand window
            elec_times.zip(elec_vals).each do |date_time, val|
              time = date_time.time
              date = date_time.date
              day_of_week = date.dayOfWeek
              # Convert the peak demand to kW
              val_J_per_hr = val/int_len_hrs.value
              val_kW = OpenStudio::convert(val_J_per_hr, "J/h", "kW").get
              
              #puts("#{val_kW}kW; #{date}; #{time}; #{day_of_week.valueName}")
              
              # Skip times outside of the correct months
              next if date_time < june_first || date_time > sept_thirtieth
              # Skip times before 2pm and after 6pm
              next if time < two_pm || time > six_pm
              
              #puts("VALID #{val_kW}kW; #{date}; #{time}; #{day_of_week.valueName}")
              
              # Check peak demand against this timestep
              # and update if this timestep is higher.
              if val > electricity_peak_demand
                electricity_peak_demand = val
                electricity_peak_demand_time = date_time
              end
            end
            elec_peak_demand_timestep_J = OpenStudio::Quantity.new(electricity_peak_demand, joule_unit)
            num_int = elec.values.size
            int_len_hrs = OpenStudio::Quantity.new(hrs_sim/num_int, hrs_unit)
            elec_peak_demand_hourly_J_per_hr = elec_peak_demand_timestep_J/int_len_hrs
            electricity_peak_demand = OpenStudio::convert(elec_peak_demand_hourly_J_per_hr, kilowatt_unit).get.value
            @runner.registerValue("annual_demand_electricity_peak_demand", electricity_peak_demand, "kW")
            @runner.registerInfo("Peak Demand = #{electricity_peak_demand}kW on #{electricity_peak_demand_time}")
          else
            @runner.registerError("Peak Demand timeseries (Electricity:Facility at zone timestep) could not be found, cannot determine the informatino needed to calculate savings or incentives.")
            @runner.registerValue("annual_demand_electricity_peak_demand", 0.0, "kW")
          end
          
          #electricity_annual_avg_peak_demand
          val = @sql.electricityTotalEndUses
          if val.is_initialized
            ann_elec_gj = OpenStudio::Quantity.new(val.get, gigajoule_unit)
            ann_hrs = OpenStudio::Quantity.new(hrs_sim, hrs_unit)
            elec_ann_avg_peak_demand_hourly_GJ_per_hr = ann_elec_gj/ann_hrs
            electricity_annual_avg_peak_demand = OpenStudio::convert(elec_ann_avg_peak_demand_hourly_GJ_per_hr, kilowatt_unit).get.value
            @runner.registerValue("annual_demand_electricity_annual_avg_peak_demand", electricity_annual_avg_peak_demand, "kW")
          else
            @runner.registerValue("annual_demand_electricity_annual_avg_peak_demand", 0.0, "kW")
          end
        
          #district_cooling_peak_demand
          district_cooling_peak_demand = -1.0
          ann_dist_clg_peak_demand_time = nil
          dist_clg = @sql.timeSeries(ann_env_pd, "Zone Timestep", "DistrictCooling:Facility", "")
          #deduce the timestep based on the hours simulated and the number of datapoints in the timeseries
          if dist_clg.is_initialized
            dist_clg = dist_clg.get            
            num_int = dist_clg.values.size
            int_len_hrs = OpenStudio::Quantity.new(hrs_sim/num_int, hrs_unit)
            
            # Put timeseries into array
            dist_clg_vals = []
            ann_dist_clg_vals = dist_clg.values
            for i in 0..(ann_dist_clg_vals.size - 1)
              dist_clg_vals << ann_dist_clg_vals[i]
            end            
 
            # Put values into array
            dist_clg_times = []
            ann_dist_clg_times = dist_clg.dateTimes
            for i in 0..(ann_dist_clg_times.size - 1)
              dist_clg_times << ann_dist_clg_times[i]
            end
                        
            # Loop through the time/value pairs and find the peak
            # excluding the times outside of the Xcel peak demand window
            dist_clg_times.zip(dist_clg_vals).each do |date_time, val|
              time = date_time.time
              date = date_time.date
              day_of_week = date.dayOfWeek
              # Convert the peak demand to kW
              val_J_per_hr = val/int_len_hrs.value
              val_kW = OpenStudio::convert(val_J_per_hr, "J/h", "kW").get
              
              #puts("#{val_kW}kW; #{date}; #{time}; #{day_of_week.valueName}")
              
              # Skip times outside of the correct months
              next if date_time < june_first || date_time > sept_thirtieth
              # Skip times before 2pm and after 6pm
              next if time < two_pm || time > six_pm
              
              #puts("VALID #{val_kW}kW; #{date}; #{time}; #{day_of_week.valueName}")
              
              # Check peak demand against this timestep
              # and update if this timestep is higher.
              if val > district_cooling_peak_demand
                district_cooling_peak_demand = val
                ann_dist_clg_peak_demand_time = date_time
              end
            end
            dist_clg_peak_demand_timestep_J = OpenStudio::Quantity.new(district_cooling_peak_demand, joule_unit)
            num_int = dist_clg.values.size
            int_len_hrs = OpenStudio::Quantity.new(hrs_sim/num_int, hrs_unit)
            dist_clg_peak_demand_hourly_J_per_hr = dist_clg_peak_demand_timestep_J/int_len_hrs
            district_cooling_peak_demand = OpenStudio::convert(dist_clg_peak_demand_hourly_J_per_hr, kilowatt_unit).get.value
            @runner.registerValue("annual_demand_district_cooling_peak_demand", district_cooling_peak_demand, "kW")
            @runner.registerInfo("District Cooling Peak Demand = #{district_cooling_peak_demand}kW on #{ann_dist_clg_peak_demand_time}")
          else
            @runner.registerValue("annual_demand_district_cooling_peak_demand", 0.0, "kW")
          end
          
        else
          @runner.registerError("Could not find an annual run period")
          return false
        end

      #end demand

      #utility_cost
      utility_cost_elems = OpenStudio::AttributeVector.new
      annual_utility_cost_map = {}   
          
        #electricity
        electricity = @sql.annualTotalCost(OpenStudio::FuelType.new("Electricity"))
        if electricity.is_initialized
          @runner.registerValue("annual_utility_cost_electricity", electricity.get, "dollars")
          annual_utility_cost_map[OpenStudio::EndUseFuelType.new("Electricity").valueName] = electricity.get
        else
          @runner.registerValue("annual_utility_cost_electricity", 0.0, "dollars")
          annual_utility_cost_map[OpenStudio::EndUseFuelType.new("Electricity").valueName] = 0.0
        end

        #electricity_consumption_charge and electricity_demand_charge
        electric_consumption_charge = 0.0
        electric_demand_charge = 0.0
        
        electric_rate_query = "SELECT value FROM tabulardatawithstrings WHERE ReportName='LEEDsummary' AND ReportForString='Entire Facility' AND TableName='EAp2-3. Energy Type Summary' AND RowName='Electricity' AND ColumnName='Utility Rate'"
        electric_rate_name = @sql.execAndReturnFirstString(electric_rate_query)
        if electric_rate_name.is_initialized
          electric_rate_name = electric_rate_name.get.strip
        
          #electricity_consumption_charge
          electric_consumption_charge_query = "SELECT value FROM tabulardatawithstrings WHERE ReportName='Tariff Report' AND ReportForString='#{electric_rate_name}' AND TableName='Categories' AND RowName='EnergyCharges (~~$~~)' AND ColumnName='Sum'"
          val = @sql.execAndReturnFirstDouble(electric_consumption_charge_query)
          if val.is_initialized
            electric_consumption_charge = val.get
          end 
  
          #electricity_demand_charge
          electric_demand_charge_query = "SELECT value FROM tabulardatawithstrings WHERE ReportName='Tariff Report' AND ReportForString='#{electric_rate_name}' AND TableName='Categories' AND RowName='DemandCharges (~~$~~)' AND ColumnName='Sum'"
          val = @sql.execAndReturnFirstDouble(electric_demand_charge_query)
          if val.is_initialized
            electric_demand_charge = val.get
          end 
          
        end
        @runner.registerValue("annual_utility_cost_electricity_consumption_charge", electric_consumption_charge, "dollars")
        @runner.registerValue("annual_utility_cost_electricity_demand_charge", electric_demand_charge, "dollars")

        #gas
        gas = @sql.annualTotalCost(OpenStudio::FuelType.new("Gas"))
        if gas.is_initialized
          annual_utility_cost_map[OpenStudio::EndUseFuelType.new("Gas").valueName] = gas.get
        else
          annual_utility_cost_map[OpenStudio::EndUseFuelType.new("Gas").valueName] = 0.0
        end
        
        #district_cooling
        dist_clg_cost_row_query = "SELECT RowID FROM tabulardatawithstrings WHERE ReportName='Economics Results Summary Report' AND ReportForString='Entire Facility' AND TableName='Tariff Summary' AND Value='DISTRICTCOOLING:FACILITY'"
        dist_clg_row_id = @sql.execAndReturnFirstDouble(dist_clg_cost_row_query)
        if dist_clg_row_id.is_initialized
          dist_clg_cost_query = "SELECT Value FROM tabulardatawithstrings WHERE ReportName='Economics Results Summary Report' AND ReportForString='Entire Facility' AND TableName='Tariff Summary' AND RowID=#{dist_clg_row_id.get} and ColumnName='Annual Cost (~~$~~)'"
          district_cooling = @sql.execAndReturnFirstDouble(dist_clg_cost_query)
          if district_cooling.is_initialized
            annual_utility_cost_map[OpenStudio::EndUseFuelType.new("DistrictCooling").valueName] = district_cooling.get
          else
            annual_utility_cost_map[OpenStudio::EndUseFuelType.new("DistrictCooling").valueName] = 0.0
          end
        else
          annual_utility_cost_map[OpenStudio::EndUseFuelType.new("DistrictCooling").valueName] = 0.0          
        end 
        
        #district_heating
        dist_htg_cost_row_query = "SELECT RowID FROM tabulardatawithstrings WHERE ReportName='Economics Results Summary Report' AND ReportForString='Entire Facility' AND TableName='Tariff Summary' AND Value='DISTRICTHEATING:FACILITY'"
        dist_htg_row_id = @sql.execAndReturnFirstDouble(dist_htg_cost_row_query)
        if dist_htg_row_id.is_initialized
          dist_htg_cost_query = "SELECT Value FROM tabulardatawithstrings WHERE ReportName='Economics Results Summary Report' AND ReportForString='Entire Facility' AND TableName='Tariff Summary' AND RowID=#{dist_htg_row_id.get} and ColumnName='Annual Cost (~~$~~)'"
          district_heating = @sql.execAndReturnFirstDouble(dist_htg_cost_query)
          if district_heating.is_initialized
            annual_utility_cost_map[OpenStudio::EndUseFuelType.new("DistrictHeating").valueName] = district_heating.get
          else
            annual_utility_cost_map[OpenStudio::EndUseFuelType.new("DistrictHeating").valueName] = 0.0
          end
        else
          annual_utility_cost_map[OpenStudio::EndUseFuelType.new("DistrictHeating").valueName] = 0.0
        end
        
        #water
        water = @sql.annualTotalCost(OpenStudio::FuelType.new("Water"))
        if water.is_initialized
          annual_utility_cost_map[OpenStudio::EndUseFuelType.new("Water").valueName] = water.get
        else
          annual_utility_cost_map[OpenStudio::EndUseFuelType.new("Water").valueName] = 0.0
        end
        
        #total
        total_query = "SELECT Value from tabulardatawithstrings where (reportname = 'Economics Results Summary Report') and (ReportForString = 'Entire Facility') and (TableName = 'Annual Cost') and (ColumnName ='Total') and (((RowName = 'Cost') and (Units = '~~$~~')) or (RowName = 'Cost (~~$~~)'))"
        total = @sql.execAndReturnFirstDouble(total_query)        

        #other_energy
        # Subtract off the already accounted for fuel types from the total
        # to account for fuels on custom meters where the fuel type is not known.
        prev_tot = 0.0
        annual_utility_cost_map.each do |fuel, val|
          prev_tot += val
        end
        if total.is_initialized
          other_val = total.get - prev_tot
          annual_utility_cost_map[OpenStudio::EndUseFuelType.new("AdditionalFuel").valueName] = other_val
        else
          annual_utility_cost_map[OpenStudio::EndUseFuelType.new("AdditionalFuel").valueName] = 0.0
        end    
    
        # export remaining costs in the correct order
        # gas
        @runner.registerValue("annual_utility_cost_gas", annual_utility_cost_map[OpenStudio::EndUseFuelType.new("Gas").valueName], "dollars")
        # other_energy
        @runner.registerValue("annual_utility_cost_other_energy", annual_utility_cost_map[OpenStudio::EndUseFuelType.new("AdditionalFuel").valueName], "dollars")        
        # district_cooling
        @runner.registerValue("annual_utility_cost_district_cooling", annual_utility_cost_map[OpenStudio::EndUseFuelType.new("DistrictCooling").valueName], "dollars")   
        # district_heating
        @runner.registerValue("annual_utility_cost_district_heating", annual_utility_cost_map[OpenStudio::EndUseFuelType.new("DistrictHeating").valueName], "dollars")
        # water
        @runner.registerValue("annual_utility_cost_water", annual_utility_cost_map[OpenStudio::EndUseFuelType.new("Water").valueName], "dollars")
        # total
        if total.is_initialized
          @runner.registerValue("annual_utility_cost_total", total.get, "dollars")
        else
          @runner.registerValue("annual_utility_cost_total", 0.0, "dollars")
        end 
    
        #end_uses - utility costs by end use using average blended cost  

          #map to store the costs by end use
          cost_by_end_use = {}
        
          #fill the map with 0.0's to start
          end_use_cat_types.each do |end_use_cat_type|
            cost_by_end_use[end_use_cat_type] = 0.0
          end
        
          #only attempt to get monthly data if enduses table is available
          if @sql.endUses.is_initialized
            end_uses_table = @sql.endUses.get
            #loop through all the fuel types
            end_use_fuel_types.each do |end_use_fuel_type|
              #get the annual total cost for this fuel type
              ann_cost = annual_utility_cost_map[end_use_fuel_type.valueName]
              #get the total annual usage for this fuel type in all end use categories
              #loop through all end uses, adding the annual usage value to the aggregator
              ann_usg = 0.0
              end_use_cat_types.each do |end_use_cat_type|
                ann_usg += end_uses_table.getEndUse(end_use_fuel_type,end_use_cat_type)
              end
              #figure out the annual blended rate for this fuel type
              avg_ann_rate = 0.0
              if ann_cost > 0 && ann_usg > 0
                avg_ann_rate = ann_cost/ann_usg
              end
              #for each end use category, figure out the cost if using
              #the avg ann rate; add this cost to the map
              end_use_cat_types.each do |end_use_cat_type|
                cost_by_end_use[end_use_cat_type] += end_uses_table.getEndUse(end_use_fuel_type,end_use_cat_type) * avg_ann_rate
              end
            end
            #loop through the end uses and record the annual total cost based on the avg annual rate
            end_use_cat_types.each do |end_use_cat_type|
              #record the value
              @runner.registerValue("annual_utility_cost_end_uses_#{end_use_map[end_use_cat_type.value]}", cost_by_end_use[end_use_cat_type], "dollars") 
            end
          else
            @runner.registerError("End-Use table not available in results; could not retrieve monthly costs by end use")
            return false
          end
          
        #end end_uses

      #end utility_costs

    #end annual

    #monthly

      #consumption

        #loop through all end uses
        end_use_cat_types.each do |end_use_cat|   
          end_use_name = end_use_map[end_use_cat.value]
          #in each end use, loop through all fuel types
          end_use_fuel_types.each do |end_use_fuel_type|  
            fuel_type_name = fuel_type_alias_map[end_use_fuel_type.value]
            ann_energy_cons = 0.0
            #in each end use, loop through months and get monthly enedy consumption
            months.each_with_index do |month, i|
              mon_energy_cons = 0.0
              val = @sql.energyConsumptionByMonth(end_use_fuel_type, end_use_cat, month)
              if val.is_initialized
                monthly_consumption_J = OpenStudio::Quantity.new(val.get, joule_unit)
                monthly_consumption_GJ = OpenStudio::convert(monthly_consumption_J, gigajoule_unit).get.value
                mon_energy_cons = monthly_consumption_GJ
                ann_energy_cons += monthly_consumption_GJ
              end
              #record the monthly value
              if end_use_fuel_type == OpenStudio::EndUseFuelType.new("Water")
                @runner.registerValue("monthly_consumption_#{end_use_name}_#{fuel_type_name}_month_#{i + 1}", mon_energy_cons, "m^3")
              else
                @runner.registerValue("monthly_consumption_#{end_use_name}_#{fuel_type_name}_month_#{i + 1}", mon_energy_cons, "GJ")
              end
                
            end
            #record the annual total
            @runner.registerValue("monthly_consumption_#{end_use_name}_#{fuel_type_name}_year", ann_energy_cons, "GJ")
          end
        end
      #end consumption

      #create a unit to use
      watt_unit = OpenStudio::createUnit("W").get
      kilowatt_unit = OpenStudio::createUnit("kW").get  
      
      #demand

        #loop through all end uses
        end_use_cat_types.each do |end_use_cat|   
          end_use_name = end_use_map[end_use_cat.value]
          #in each end use, loop through all fuel types
          end_use_fuel_types.each do |end_use_fuel_type|  
            fuel_type_name = fuel_type_alias_map[end_use_fuel_type.value]
            ann_peak_demand = 0.0
            #in each end use, loop through months and get monthly enedy consumption
            months.each_with_index do |month, i|
              mon_peak_demand = 0.0
              val = @sql.peakEnergyDemandByMonth(end_use_fuel_type, end_use_cat, month)
              if val.is_initialized
                mon_peak_demand_W = OpenStudio::Quantity.new(val.get, watt_unit)
                mon_peak_demand = OpenStudio::convert(mon_peak_demand_W, kilowatt_unit).get.value
              end
              #record the monthly value
              @runner.registerValue("monthly_demand_#{end_use_name}_#{fuel_type_name}_month_#{i + 1}", mon_peak_demand, "kW")
              #if month peak demand > ann peak demand make this new ann peak demand
              if mon_peak_demand > ann_peak_demand
                ann_peak_demand = mon_peak_demand
              end
            end
            #record the annual peak demand
            @runner.registerValue("monthly_demand_#{end_use_name}_#{fuel_type_name}_year", ann_peak_demand, "kW")
          end
        end
      #end demand
      
    #end monthly

    return true
    
  end #end create_results  
    
end    
    