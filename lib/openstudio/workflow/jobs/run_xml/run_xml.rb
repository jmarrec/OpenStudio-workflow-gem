######################################################################
#  Copyright (c) 2008-2014, Alliance for Sustainable Energy.
#  All rights reserved.
#
#  This library is free software; you can redistribute it and/or
#  modify it under the terms of the GNU Lesser General Public
#  License as published by the Free Software Foundation; either
#  version 2.1 of the License, or (at your option) any later version.
#
#  This library is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#  Lesser General Public License for more details.
#
#  You should have received a copy of the GNU Lesser General Public
#  License along with this library; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
######################################################################

require 'libxml'

# This actually belongs as another class that gets added as a state dynamically
class RunXml

  CRASH_ON_NO_WORKFLOW_VARIABLE = FALSE
  # RunXml
  def initialize(directory, logger, adapter, options = {})
    defaults = {use_monthly_reports: false, xml_library_root_path: '.'}
    @options = defaults.merge(options)
    @directory = directory
    # TODO: there is a base number of arguments that each job will need including @run_directory. abstract it out.
    @run_directory = "#{@directory}/run"
    @adapter = adapter
    @results = {}
    @logger = logger
    @logger.info "#{self.class} passed the following options #{@options}"

    # initialize instance variables that are needed in the perform section
    @weather_filename = nil
    @weather_directory = File.join(@directory,"weather")
    @model_xml = nil
    @model = nil
    @model_idf = nil
    @analysis_json = nil
    # TODO: rename datapoint_json to just datapoint
    @datapoint_json = nil
    @output_attributes = []
    @report_measures = []
    @measure_type_lookup = {
        :openstudio_measure => 'RubyMeasure',
        :energyplus_measure => 'EnergyPlusMeasure',
        :reporting_measure => 'ReportingMeasure'
    }
  end


  def perform
    @logger.info "Calling #{__method__} in the #{self.class} class"
    @logger.info "Current directory is #{@directory}"

    @logger.info "Retrieving datapoint and problem"
    @datapoint_json = @adapter.get_datapoint(@directory, @options)
    @analysis_json = @adapter.get_problem(@directory, @options)

    @space_lib_path = File.expand_path("#{@directory}/lib/openstudio_xml/space_types")
    if @analysis_json && @analysis_json[:analysis]
      @model_xml = load_xml_model
      @weather_filename = load_weather_file

      apply_xml_measures

      # TODO: naming convention for the output attribute files
      @logger.info "Measure output attributes are #{@output_attributes}"
      File.open("#{@run_directory}/#{self.class.name.downcase}_measure_attributes.json", 'w') {
          |f| f << JSON.pretty_generate(@output_attributes)
      }
    end

    create_osm_from_xml

    @results
  end

  private

  def load_xml_model
    model = nil
    @logger.info 'Loading seed model'

    if @analysis_json[:analysis][:seed]
      @logger.info "Seed model is #{@analysis_json[:analysis][:seed]}"
      if @analysis_json[:analysis][:seed][:path]

        # assume that the seed model has been placed in the directory
        baseline_model_path = File.expand_path(
            File.join(@directory, @analysis_json[:analysis][:seed][:path]))

        if File.exist? baseline_model_path
          @logger.info "Reading in baseline model #{baseline_model_path}"
          model = LibXML::XML::Document.file(baseline_model_path)
          fail 'XML model is nil' if model.nil?

          model.save("#{@run_directory}/original.xml")
        else
          fail "Seed model '#{baseline_model_path}' did not exist"
        end
      else
        fail 'No seed model path in JSON defined'
      end
    else
      fail 'No seed model block'
    end

    model
  end

  # Save the weather file to the instance variable
  def load_weather_file
    weather_filename = nil
    if @analysis_json[:analysis][:weather_file]
      if @analysis_json[:analysis][:weather_file][:path]
        # This last(4) needs to be cleaned up.  Why don't we know the path of the file?
        # assume that the seed model has been placed in the directory
        weather_filename = File.expand_path(
            File.join(@directory, @analysis_json[:analysis][:weather_file][:path]))
        unless File.exist?(weather_filename)
          @logger.warn "Could not find weather file for simulation #{weather_filename}. Will continue because may change"
        end


      else
        fail 'No weather file path defined'
      end
    else
      fail 'No weather file block defined'
    end

    weather_filename
  end

  def create_osm_from_xml
    # Save the final state of the XML file
    xml_filename = "#{@run_directory}/final.xml"
    @model_xml.save(xml_filename)

    @logger.info 'Starting XML to OSM translation'

    # TODO move the analysis dir to a general setting
    require "#{@directory}/lib/openstudio_xml/main"
    @logger.info "The weather file is #{@weather_filename}"
    osxt = Main.new(@weather_directory, @space_lib_path)
    osm, idf, new_xml, building_name, weather_file = osxt.process(@model_xml.to_s, false, true)
    if osm
      osm_filename = "#{@run_directory}/xml_out.osm"
      File.open(osm_filename, 'w') { |f| f << osm }

      @logger.info 'Finished XML to OSM translation'
    else
      fail 'No OSM model output from XML translation'
    end

    @results[:osm_filename] = File.expand_path(osm_filename)
    @results[:xml_filename] = File.expand_path(xml_filename)
    @results[:weather_filename] = File.expand_path(File.join(@weather_directory,@weather_filename))
  end

  def apply_xml_measures
    # iterate over the workflow and grab the measures
    if @analysis_json[:analysis][:problem] && @analysis_json[:analysis][:problem][:workflow]
      @analysis_json[:analysis][:problem][:workflow].each do |wf|
        if wf[:measure_type] == 'XmlMeasure'
          # need to map the variables to the XML classes
          measure_path = wf[:measure_definition_directory]
          measure_name = wf[:measure_definition_class_name]

          @logger.info "XML Measure path is #{measure_path}"
          @logger.info "XML Measure name is #{measure_name}"

          @logger.info "Loading measure in relative path #{measure_path}"
          measure_file_path = File.expand_path(
              File.join(@directory, @options[:analysis_root_path], measure_path, 'measure.rb'))
          fail "Measure file does not exist #{measure_name} in #{measure_file_path}" unless File.exist? measure_file_path

          require measure_file_path
          measure = Object.const_get(measure_name).new

          @logger.info "iterate over arguments for workflow item #{wf[:name]}"

          # The Argument hash in the workflow json file looks like the following
          # {
          #    "display_name": "Set XPath",
          #    "machine_name": "set_xpath",
          #    "name": "xpath",
          #    "value": "/building/blocks/block/envelope/surfaces/window/layout/wwr",
          #    "uuid": "440dcce0-7663-0131-41f1-14109fdf0b37",
          #    "version_uuid": "440e4bd0-7663-0131-41f2-14109fdf0b37"
          # }
          args = {}
          if wf[:arguments]
            wf[:arguments].each do |wf_arg|
              if wf_arg[:value]
                @logger.info "Setting argument value #{wf_arg[:name]} to #{wf_arg[:value]}"
                # Note that these measures have symbolized hash keys and not strings.  I really want indifferential access here!
                args[wf_arg[:name].to_sym] = wf_arg[:value]
              end
            end
          end

          variables_found = false
          @logger.info "iterate over variables for workflow item #{wf[:name]}"
          if wf[:variables]
            wf[:variables].each do |wf_var|
              # Argument hash in workflow looks like the following
              # "argument": {
              #    "display_name": "Window-To-Wall Ratio",
              #    "machine_name": "window_to_wall_ratio",
              #    "name": "value",
              #    "uuid": "a0618d15-bb0b-4494-a72f-8ad628693a7e",
              #    "version_uuid": "b33cf6b0-f1aa-4706-afab-9470e6bd1912"
              # },
              variable_uuid = wf_var[:uuid].to_sym # this is what the variable value is set to
              if wf_var[:argument]
                variable_name = wf_var[:argument][:name]

                # Get the value from the data point json that was set via R / Problem Formulation
                if @datapoint_json[:data_point]
                  if @datapoint_json[:data_point][:set_variable_values]
                    if @datapoint_json[:data_point][:set_variable_values][variable_uuid]
                      @logger.info "Setting variable #{variable_name} to #{@datapoint_json[:data_point][:set_variable_values][variable_uuid]}"

                      args[wf_var[:argument][:name].to_sym] = @datapoint_json[:data_point][:set_variable_values][variable_uuid]
                      args["#{wf_var[:argument][:name]}_machine_name".to_sym] = wf_var[:argument][:machine_name]
                      args["#{wf_var[:argument][:name]}_type".to_sym] = wf_var[:value_type] if wf_var[:value_type]
                      @logger.info "Setting the machine name for argument '#{wf_var[:argument][:name]}' to '#{args["#{wf_var[:argument][:name]}_machine_name".to_sym]}'"

                      # Catch a very specific case where the weather file has to be changed
                      if wf[:name] == 'location'
                        @logger.warn "VERY SPECIFIC case to change the location to #{@datapoint_json[:data_point][:set_variable_values][variable_uuid]}"
                        @weather_filename = @datapoint_json[:data_point][:set_variable_values][variable_uuid]
                      end
                      variables_found = true
                    else
                      @logger.info "Value for variable '#{variable_name}:#{variable_uuid}' not set in datapoint object"
                      fail "Value for variable '#{variable_name}:#{variable_uuid}' not set in datapoint object" if CRASH_ON_NO_WORKFLOW_VARIABLE
                      break
                    end
                  else
                    fail 'No block for set_variable_values in data point record'
                  end
                else
                  fail 'No block for data_point in data_point record'
                end
              end
            end
          end

          # Run the XML Measure
          xml_changed = measure.run(@model_xml, nil, args) if variables_found

          # save the JSON with the changed values
          # the measure has to implement the "results_to_json" method
          measure.results_to_json("#{@run_directory}/#{wf[:name]}_results.json")

          # TODO: do we want to do this?
          #ros.communicate_intermediate_result(measure.variable_values)

          @logger.info "Finished applying measure workflow #{wf[:name]} with change flag set to '#{xml_changed}'"
        end
      end
    end

  end
end