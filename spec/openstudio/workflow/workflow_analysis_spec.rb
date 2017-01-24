require_relative './../../spec_helper'
require 'json-schema'

describe 'OSW Integration' do
  it 'should run empty OSW file' do
    osw_path = File.join(__FILE__, './../../../files/empty_seed_osw/empty.osw')
    run_options = {
        debug: true
    }
    k = OpenStudio::Workflow::Run.new osw_path, run_options
    expect(k).to be_instance_of OpenStudio::Workflow::Run
    expect(k.run).to eq :finished
  end

  it 'should run compact OSW file' do
    osw_path = File.expand_path('./../../../files/compact_osw/compact.osw', __FILE__)
    osw_out_path = osw_path.gsub(File.basename(osw_path), 'out.osw')

    FileUtils.rm_rf(osw_out_path) if File.exist?(osw_out_path)
    expect(File.exist?(osw_out_path)).to eq false

    run_options = {
        debug: true
    }
    k = OpenStudio::Workflow::Run.new osw_path, run_options
    expect(k).to be_instance_of OpenStudio::Workflow::Run
    expect(k.run).to eq :finished

    expect(File.exist?(osw_out_path)).to eq true

    osw_out = nil
    File.open(osw_out_path, 'r') do |file|
      osw_out = JSON.parse(file.read, symbolize_names: true)
    end

    expect(osw_out).to be_instance_of Hash
    expect(osw_out[:completed_status]).to eq 'Success'
    expect(osw_out[:steps]).to be_instance_of Array
    expect(osw_out[:steps].size).to be > 0
    osw_out[:steps].each do |step|
      expect(step[:result]).to_not be_nil
    end
  end

  it 'should run an extended OSW file' do
    osw_path = File.expand_path('./../../../files/extended_osw/example/workflows/extended.osw', __FILE__)
    run_options = {
        debug: true
    }
    k = OpenStudio::Workflow::Run.new osw_path, run_options
    expect(k).to be_instance_of OpenStudio::Workflow::Run
    expect(k.run).to eq :finished
  end

  it 'should run an alternate path OSW file' do
    osw_path = File.expand_path('./../../../files/alternate_paths/osw_and_stuff/in.osw', __FILE__)
    run_options = {
        debug: true
    }
    k = OpenStudio::Workflow::Run.new osw_path, run_options
    expect(k).to be_instance_of OpenStudio::Workflow::Run
    expect(k.run).to eq :finished
  end

  it 'should run OSW file with skips' do
    osw_path = File.expand_path('./../../../files/skip_osw/skip.osw', __FILE__)
    run_options = {
        debug: true
    }
    k = OpenStudio::Workflow::Run.new osw_path, run_options
    expect(k).to be_instance_of OpenStudio::Workflow::Run
    expect(k.run).to eq :finished
  end

  it 'should run OSW file with handle arguments' do
    osw_path = File.expand_path('./../../../files/handle_args_osw/handle_args.osw', __FILE__)
    run_options = {
        debug: true
    }
    k = OpenStudio::Workflow::Run.new osw_path, run_options
    expect(k).to be_instance_of OpenStudio::Workflow::Run
    expect(k.run).to eq :finished
  end

  it 'should run OSW with output requests file' do
    osw_path = File.expand_path('./../../../files/output_request_osw/output_request.osw', __FILE__)
    osw_out_path = osw_path.gsub(File.basename(osw_path), 'out.osw')

    FileUtils.rm_rf(osw_out_path) if File.exist?(osw_out_path)
    expect(File.exist?(osw_out_path)).to eq false

    run_options = {
        debug: true
    }
    k = OpenStudio::Workflow::Run.new osw_path, run_options
    expect(k).to be_instance_of OpenStudio::Workflow::Run
    expect(k.run).to eq :finished

    expect(File.exist?(osw_out_path)).to eq true

    osw_out = nil
    File.open(osw_out_path, 'r') do |file|
      osw_out = JSON.parse(file.read, symbolize_names: true)
    end

    expect(osw_out).to be_instance_of Hash
    expect(osw_out[:completed_status]).to eq 'Success'
    expect(osw_out[:steps]).to be_instance_of Array
    expect(osw_out[:steps].size).to be > 0
    osw_out[:steps].each do |step|
      expect(step[:result]).to_not be_nil
    end

    idf_out_path = osw_path.gsub(File.basename(osw_path), 'in.idf')

    expect(File.exist?(idf_out_path)).to eq true

    workspace = OpenStudio::Workspace.load(idf_out_path)
    expect(workspace.empty?).to eq false

    workspace = workspace.get

    targets = {}
    targets['Electricity:Facility'] = false
    targets['Gas:Facility'] = false
    targets['District Cooling Chilled Water Rate'] = false
    targets['District Cooling Mass Flow Rate'] = false
    targets['District Cooling Inlet Temperature'] = false
    targets['District Cooling Outlet Temperature'] = false
    targets['District Heating Hot Water Rate'] = false
    targets['District Heating Mass Flow Rate'] = false
    targets['District Heating Inlet Temperature'] = false
    targets['District Heating Outlet Temperature'] = false

    workspace.getObjectsByType('Output:Variable'.to_IddObjectType).each do |object|
      name = object.getString(1)
      expect(name.empty?).to eq false
      name = name.get
      targets[name] = true
    end

    targets.each_key do |key|
      expect(targets[key]).to eq true
    end

    # make sure that the reports exist
    report_filename = File.join(File.dirname(osw_path), 'reports', '003_DencityReports_report_timeseries.csv')
    expect(File.exist?(report_filename)).to eq true
    report_filename = File.join(File.dirname(osw_path), 'reports', '004_openstudio_results_report.html')
    expect(File.exist?(report_filename)).to eq true
    report_filename = File.join(File.dirname(osw_path), 'reports', 'eplustbl.html')
    expect(File.exist?(report_filename)).to eq true
  end

  it 'should run OSW file with web adapter' do
    require 'openstudio/workflow/adapters/output/web'

    osw_path = File.expand_path('./../../../files/web_osw/web.osw', __FILE__)
    osw_out_path = osw_path.gsub(File.basename(osw_path), 'out.osw')
    run_dir = File.join(File.dirname(osw_path), 'run')

    FileUtils.rm_rf(osw_out_path) if File.exist?(osw_out_path)
    expect(File.exist?(osw_out_path)).to eq false

    output_adapter = OpenStudio::Workflow::OutputAdapter::Web.new(output_directory: run_dir, url: 'http://www.example.com')

    run_options = {
        debug: true,
        output_adapter: output_adapter
    }
    k = OpenStudio::Workflow::Run.new osw_path, run_options
    expect(k).to be_instance_of OpenStudio::Workflow::Run
    expect(k.run).to eq :finished

    expect(File.exist?(osw_out_path)).to eq true

    osw_out = nil
    File.open(osw_out_path, 'r') do |file|
      osw_out = JSON.parse(file.read, symbolize_names: true)
    end

    expect(osw_out).to be_instance_of Hash
    expect(osw_out[:completed_status]).to eq 'Success'
    expect(osw_out[:steps]).to be_instance_of Array
    expect(osw_out[:steps].size).to be > 0
    osw_out[:steps].each do |step|
      expect(step[:result]).to_not be_nil
    end
  end

  it 'should run OSW file with socket adapter' do
    require 'openstudio/workflow/adapters/output/socket'

    osw_path = File.expand_path('./../../../files/socket_osw/socket.osw', __FILE__)
    osw_out_path = osw_path.gsub(File.basename(osw_path), 'out.osw')
    run_dir = File.join(File.dirname(osw_path), 'run')

    FileUtils.rm_rf(osw_out_path) if File.exist?(osw_out_path)
    expect(File.exist?(osw_out_path)).to eq false

    port = 2000
    content = ''

    server = TCPServer.open('localhost', port)
    t = Thread.new do
      while client = server.accept
        while line = client.gets
          content += line
        end
      end
    end

    output_adapter = OpenStudio::Workflow::OutputAdapter::Socket.new(output_directory: run_dir, port: port)

    run_options = {
        debug: true,
        output_adapter: output_adapter
    }
    k = OpenStudio::Workflow::Run.new osw_path, run_options
    expect(k).to be_instance_of OpenStudio::Workflow::Run
    expect(k.run).to eq :finished

    expect(File.exist?(osw_out_path)).to eq true

    Thread.kill(t)

    expect(content).to match(/Starting state initialization/)
    expect(content).to match(/Processing Data Dictionary/)
    expect(content).to match(/Writing final SQL reports/)

    osw_out = nil
    File.open(osw_out_path, 'r') do |file|
      osw_out = JSON.parse(file.read, symbolize_names: true)
    end

    expect(osw_out).to be_instance_of Hash
    expect(osw_out[:completed_status]).to eq 'Success'
    expect(osw_out[:steps]).to be_instance_of Array
    expect(osw_out[:steps].size).to be > 0
    osw_out[:steps].each do |step|
      expect(step[:result]).to_not be_nil
    end
  end

  it 'should run OSW file with no epw file' do
    osw_path = File.expand_path('./../../../files/no_epw_file_osw/no_epw_file.osw', __FILE__)
    osw_out_path = osw_path.gsub(File.basename(osw_path), 'out.osw')
    run_dir = File.join(File.dirname(osw_path), 'run')

    FileUtils.rm_rf(osw_out_path) if File.exist?(osw_out_path)
    expect(File.exist?(osw_out_path)).to eq false

    run_options = {
        debug: true
    }
    k = OpenStudio::Workflow::Run.new osw_path, run_options
    expect(k).to be_instance_of OpenStudio::Workflow::Run
    expect(k.run).to eq :finished

    expect(File.exist?(osw_out_path)).to eq true

    osw_out = nil
    File.open(osw_out_path, 'r') do |file|
      osw_out = JSON.parse(file.read, symbolize_names: true)
    end

    expect(osw_out).to be_instance_of Hash
    expect(osw_out[:completed_status]).to eq 'Success'
    expect(osw_out[:steps]).to be_instance_of Array
    expect(osw_out[:steps].size).to be > 0
    osw_out[:steps].each do |step|
      expect(step[:result]).to_not be_nil
    end
  end

  it 'should run OSW file in measure only mode' do
    osw_path = File.expand_path('./../../../files/measures_only_osw/measures_only.osw', __FILE__)
    osw_out_path = osw_path.gsub(File.basename(osw_path), 'out.osw')
    run_dir = File.join(File.dirname(osw_path), 'run')

    FileUtils.rm_rf(osw_out_path) if File.exist?(osw_out_path)
    expect(File.exist?(osw_out_path)).to eq false

    run_options = {
        debug: true
    }
    run_options[:jobs] = [
        {state: :queued, next_state: :initialization, options: {initial: true}},
        {state: :initialization, next_state: :os_measures, job: :RunInitialization,
         file: 'openstudio/workflow/jobs/run_initialization.rb', options: {}},
        {state: :os_measures, next_state: :translator, job: :RunOpenStudioMeasures,
         file: 'openstudio/workflow/jobs/run_os_measures.rb', options: {}},
        {state: :translator, next_state: :ep_measures, job: :RunTranslation,
         file: 'openstudio/workflow/jobs/run_translation.rb', options: {}},
        {state: :ep_measures, next_state: :finished, job: :RunEnergyPlusMeasures,
         file: 'openstudio/workflow/jobs/run_ep_measures.rb', options: {}},
        {state: :postprocess, next_state: :finished, job: :RunPostprocess,
         file: 'openstudio/workflow/jobs/run_postprocess.rb', options: {}},
        {state: :finished},
        {state: :errored}
    ]
    k = OpenStudio::Workflow::Run.new osw_path, run_options
    expect(k).to be_instance_of OpenStudio::Workflow::Run
    expect(k.run).to eq :finished

    expect(File.exist?(osw_out_path)).to eq true

    osw_out = nil
    File.open(osw_out_path, 'r') do |file|
      osw_out = JSON.parse(file.read, symbolize_names: true)
    end

    expect(osw_out).to be_instance_of Hash
    expect(osw_out[:completed_status]).to eq 'Success'
    expect(osw_out[:steps]).to be_instance_of Array
    expect(osw_out[:steps].size).to be > 0
    osw_out[:steps].each do |step|
      expect(step[:result]).to_not be_nil
    end
  end

  it 'should run OSW with display name or value for choice arguments' do
    osw_path = File.expand_path('./../../../files/value_or_displayname_choice_osw/value_or_displayname_choice.osw', __FILE__)
    osw_out_path = osw_path.gsub(File.basename(osw_path), 'out.osw')

    FileUtils.rm_rf(osw_out_path) if File.exist?(osw_out_path)
    expect(File.exist?(osw_out_path)).to eq false

    run_options = {
        debug: true
    }
    k = OpenStudio::Workflow::Run.new osw_path, run_options
    expect(k).to be_instance_of OpenStudio::Workflow::Run
    expect(k.run).to eq :finished

    expect(File.exist?(osw_out_path)).to eq true

    osw_out = nil
    File.open(osw_out_path, 'r') do |file|
      osw_out = JSON.parse(file.read, symbolize_names: true)
    end

    expect(osw_out).to be_instance_of Hash
    expect(osw_out[:completed_status]).to eq 'Success'
    expect(osw_out[:steps]).to be_instance_of Array
    expect(osw_out[:steps].size).to be > 0
    osw_out[:steps].each do |step|
      expect(step[:result]).to_not be_nil
    end
  end

  it 'should error out nicely' do
    osw_path = File.expand_path('./../../../files/reporting_measure_error/reporting_measure_error.osw', __FILE__)
    osw_out_path = osw_path.gsub(File.basename(osw_path), 'out.osw')

    FileUtils.rm_rf(osw_out_path) if File.exist?(osw_out_path)
    expect(File.exist?(osw_out_path)).to eq false

    run_options = {
        debug: true
    }
    k = OpenStudio::Workflow::Run.new osw_path, run_options
    expect(k).to be_instance_of OpenStudio::Workflow::Run
    expect(k.run).to eq :errored

    expect(File.exist?(osw_out_path)).to eq true

    osw_out = nil
    File.open(osw_out_path, 'r') do |file|
      osw_out = JSON.parse(file.read, symbolize_names: true)
    end

    expect(osw_out).to be_instance_of Hash
    expect(osw_out[:completed_status]).to eq 'Fail'
    expect(osw_out[:steps]).to be_instance_of Array
    expect(osw_out[:steps].size).to be > 0
    osw_out[:steps].each do |step|
      expect(step[:result]).to_not be_nil
    end

    expected_r = /Peak Demand timeseries \(Electricity:Facility at zone timestep\) could not be found, cannot determine the informati(no|on) needed to calculate savings or incentives./
    expect(osw_out[:steps].last[:result][:step_errors].last).to match expected_r

    idf_out_path = osw_path.gsub(File.basename(osw_path), 'in.idf')
    expect(File.exist?(idf_out_path)).to eq true

    # even if it fails, make sure that we save off the datapoint.zip
    zip_path = osw_path.gsub(File.basename(osw_path), 'data_point.zip')
    expect(File.exist?(zip_path)).to eq false
  end
  
  it 'should associate results with the correct step' do
    (1..2).each do |i|
      osw_path = File.expand_path("./../../../files/results_in_order/data_point_#{i}/data_point.osw", __FILE__)
      osw_out_path = osw_path.gsub(File.basename(osw_path), 'out.osw')

      FileUtils.rm_rf(osw_out_path) if File.exist?(osw_out_path)
      expect(File.exist?(osw_out_path)).to eq false
      
      if !File.exist?(osw_out_path)
        run_options = {
            debug: true
        }
        k = OpenStudio::Workflow::Run.new osw_path, run_options
        expect(k).to be_instance_of OpenStudio::Workflow::Run
        expect(k.run).to eq :finished
      end
      
      expect(File.exist?(osw_out_path)).to eq true
      
      osw_out = nil
      File.open(osw_out_path, 'r') do |file|
        osw_out = JSON.parse(file.read, symbolize_names: true)
      end

      expect(osw_out).to be_instance_of Hash
      expect(osw_out[:completed_status]).to eq 'Success'
      expect(osw_out[:steps]).to be_instance_of Array
      expect(osw_out[:steps].size).to be == 3
      osw_out[:steps].each do |step|
        expect(step[:arguments]).to_not be_nil
        
        arguments = step[:arguments]
        puts "arguments = #{arguments}"
        
        expect(step[:result]).to_not be_nil
        expect(step[:result][:step_values]).to_not be_nil
        
        step_values = step[:result][:step_values]
        puts "step_values = #{step_values}"
        
        # check that each argument is in a value
        skipped = false
        arguments.each_pair do |argument_name, argument_value|
          argument_name = argument_name.to_s
          if argument_name == '__SKIP__'
            skipped = argument_value
            next
          end
          
          i = step_values.find_index {|x| x[:name] == argument_name}
          expect(i).to_not be_nil
          expect(step_values[i][:value]).to be == argument_value
        end
        
        if skipped
          expect(step[:result][:step_result]).to be == "Skip"
        else
          expect(step[:result][:step_result]).to be == "Success"
        end
        
        expected_results = []
        if step[:measure_dir_name] == "XcelEDAReportingandQAQC"
          expected_results << "cash_flows_capital_type"
          expected_results << "annual_consumption_electricity"
          expected_results << "annual_consumption_gas"
        end

        expected_results.each do |expected_result|
          i = step_values.find_index {|x| x[:name] == expected_result}
          expect(i).to_not be_nil
        end
        
      end
    end
  end
  
  it 'should run OSW custom output adapter' do
    osw_path = File.expand_path('./../../../files/run_options_osw/run_options.osw', __FILE__)
    osw_out_path = osw_path.gsub(File.basename(osw_path), 'out.osw')

    FileUtils.rm_rf(osw_out_path) if File.exist?(osw_out_path)
    expect(File.exist?(osw_out_path)).to eq false
    
    custom_start_path = File.expand_path('./../../../files/run_options_osw/run/custom_started.job', __FILE__)
    FileUtils.rm_rf(custom_start_path) if File.exist?(custom_start_path)
    expect(File.exist?(custom_start_path)).to eq false
    
    custom_finished_path = File.expand_path('./../../../files/run_options_osw/run/custom_finished.job', __FILE__)
    FileUtils.rm_rf(custom_finished_path) if File.exist?(custom_finished_path)
    expect(File.exist?(custom_finished_path)).to eq false
    
    run_options = {
        debug: true
    }
    k = OpenStudio::Workflow::Run.new osw_path, run_options
    expect(k).to be_instance_of OpenStudio::Workflow::Run
    expect(k.run).to eq :finished

    expect(File.exist?(osw_out_path)).to eq true
    
    begin
      OpenStudio::RunOptions.new
      expect(File.exist?(custom_start_path)).to eq true
      expect(File.exist?(custom_finished_path)).to eq true
    rescue NameError => e
      # feature not available
    end
  end
  
  it 'should handle weather file throughout the run' do
    osw_path = File.expand_path('./../../../files/weather_file/weather_file.osw', __FILE__)
    expect(File.exist?(osw_path)).to eq true
    
    osw_out_path = osw_path.gsub(File.basename(osw_path), 'out.osw')
    FileUtils.rm_rf(osw_out_path) if File.exist?(osw_out_path)
    expect(File.exist?(osw_out_path)).to eq false

    workflow_json = nil
    begin
      workflow_json = OpenStudio::WorkflowJSON.new(OpenStudio::Path.new(osw_path))
    rescue NameError => e
      workflow = ::JSON.parse(File.read(osw_path), symbolize_names: true)
      workflow_json = WorkflowJSON_Shim.new(workflow, File.dirname(osw_path))
    end

    seed = workflow_json.seedFile
    expect(seed.empty?).to be false
    seed = workflow_json.findFile(seed.get)
    expect(seed.empty?).to be false
    
    vt = OpenStudio::OSVersion::VersionTranslator.new
    model = vt.loadModel(seed.get)
    expect(model.empty?).to be false
    
    weather_file = model.get.getOptionalWeatherFile
    expect(weather_file.empty?).to be false
    weather_file_path = weather_file.get.path
    expect(weather_file_path.empty?).to be false
    weather_file_path = workflow_json.findFile(weather_file_path.get.to_s)
    expect(weather_file_path.empty?).to be false
    expect(File.exist?(weather_file_path.get.to_s)).to be true
    expect(File.basename(weather_file_path.get.to_s)).to eq "USA_CO_Golden-NREL.724666_TMY3.epw"
    
    weather_file_path = workflow_json.weatherFile
    expect(weather_file_path.empty?).to be false
    weather_file_path = workflow_json.findFile(weather_file_path.get.to_s)
    expect(weather_file_path.empty?).to be false    
    expect(File.exist?(weather_file_path.get.to_s)).to be true
    expect(File.basename(weather_file_path.get.to_s)).to eq "USA_CA_San.Francisco.Intl.AP.724940_TMY3.epw"

    run_options = {
        debug: true
    }
    k = OpenStudio::Workflow::Run.new osw_path, run_options
    expect(k).to be_instance_of OpenStudio::Workflow::Run
    expect(k.run).to eq :finished

    expect(File.exist?(osw_out_path)).to eq true
    
    # check epw in run dir
    
    # check sql
    
    # add reporting measure to check?
    
  end
  
end
