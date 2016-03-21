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

require_relative 'util/directory'

# Run Class for OpenStudio workflow.  The data are passed in via the adapter
module OpenStudio
  module Workflow
    class Run
      include OpenStudio::Workflow::Util::Directory
      attr_accessor :registry

      attr_reader :options
      attr_reader :adapter
      attr_reader :final_state
      attr_reader :final_message
      attr_reader :job_results

      # load the default set of transitions
      #
      def self.default_transition
        [
          { from: :queued, to: :initialization },
          { from: :initialization, to: :os_measures },
          { from: :os_measures, to: :translator },
          { from: :translator, to: :ep_measures },
          { from: :ep_measures, to: :preprocess },
          { from: :preprocess, to: :simulation },
          { from: :simulation, to: :reporting_measures },
          { from: :reporting_measures, to: :postprocess },
          { from: :postprocess, to: :finished }
        ]
      end

      # load the default set of states  Note that the states of :queued of :finished need to exist for all cases.
      #
      def self.default_states
        [
          { state: :queued, options: { initial: true } },
          { state: :initialization, options: { after_enter: :run_initialization } },
          { state: :os_measures, options: { after_enter: :run_os_measures } },
          { state: :translator, options: { after_enter: :run_translation } },
          { state: :ep_measures, options: { after_enter: :run_ep_measures } },
          { state: :preprocess, options: { after_enter: :run_preprocess } },
          { state: :simulation, options: { after_enter: :run_energyplus } },
          { state: :reporting_measures, options: { after_enter: :run_reporting_measures } },
          { state: :postprocess, options: { after_enter: :run_postprocess } },
          { state: :finished },
          { state: :errored }
        ]
      end

      # Initialize a new run class
      #
      # @param [Object] adapter an instance of the adapter class. This will be mostly abstracted in the near future
      # @param [String] directory location of the OSW file to run. It is highly recommended that this be an absolute
      #   path, however if not it will be made absolute relative to the current working directory
      # @param [Hash] options ({}) A set of user-specified options that are used to override default behaviors. Some
      #   sort of definitive documentation is needed for this hash
      # @option options [Hash] :transitions Non-default transitions set (see Run#default_transition)
      # @option options [Hash] :states Non-default states set (see Run#default_states)
      # @option options [Hash] :jobs ???
      # @todo (rhorsey) establish definitive documentation on all option parameters, and btw what is the jobs hash?
      #
      def initialize(adapter, directory, options = {})
        @adapter = adapter
        @final_message = ''
        @current_state = nil
        @transitions = {}

        # Initialize some values into @registry
        @registry = Registry.new
        @registry.register(:directory) { get_directory directory }
        @registry.register(:run_directory) { get_run_dir(adapter.get_workflow(@registry[:directory]), @registry[:directory]) }
        time_logger =
        @registry.register(:time_logger) { TimeLogger.new }
        @registry.register(:workflow_arguments) { Hash.new }
        defaults = {
          transitions: OpenStudio::Workflow::Run.default_transition,
          states: OpenStudio::Workflow::Run.default_states,
          jobs: {},
          targets: [STDOUT, File.join(@registry[:run_directory], 'run.log')]
        }
        @options = defaults.merge(options)
        @job_results = {}

        # Initialize the MultiDelegator logger
        logger(@options[:targets])

        # By default blow away the entire run directory every time and recreate it
        FileUtils.rm_rf(@registry[:run_directory]) if File.exist?(@registry[:run_directory])
        FileUtils.mkdir_p(@registry[:run_directory])

        logger.info "Initializing directory #{@registry[:directory]} for simulation with options #{@options}"

        # load the state machine
        machine
      end

      # execute the workflow defined in the state object
      #
      # @todo add a catch if any job fails
      # @todo make a block method to provide feedback
      def run
        logger.info "Starting workflow in #{@registry[:directory]}"
        begin
          while @current_state != :finished && @current_state != :errored
            sleep 2
            step
          end

          logger.info 'Finished workflow - communicating results and zipping files'

          # @todo (nlong) This should be a job that handles the use case with a :guard on if @job_results[:run_postprocess]
          if @job_results[:run_reporting_measures]
            logger.info 'Sending the reporting measures results back to the adapter'
            @adapter.communicate_results @registry[:directory], @job_results[:run_reporting_measures]
          end
        ensure
          if @current_state == :errored
            @adapter.communicate_failure @registry[:directory]
          else
            @adapter.communicate_complete @registry[:directory]
          end

          logger.info 'Workflow complete'
          # Write out the TimeLogger once again in case the run_reporting_measures didn't exist
          @registry[:time_logger].save(File.join(@registry[:directory], 'profile.json'))

          # @todo (nlong) define the outputs and figure out how to show it correctly
          obj_function_array ||= ['NA']

          # Print the objective functions to the screen even though the file is being used right now
          # Note as well that we can't guarantee that the csv format will be in the right order
          puts obj_function_array.join(',')
        end

        @current_state
      end

      # Step through the states, if there is an error (e.g. exception) then go to error
      #
      def step
        next_state

        klass = OpenStudio::Workflow.new_class(@current_state, @adapter, @registry, options)
        @job_results[@current_state.to_sym] = klass.perform
      rescue => e
        step_error("#{e.message}:#{e.backtrace.join("\n")}")
      end

      # call back for when there is an exception running any of the state transitions
      #
      def step_error(*args)
        # Make sure to set the instance variable @error to true in order to stop the :step
        # event from being fired.
        @final_message = "Found error in state '#{@current_state}' with message #{args}}"
        logger.error @final_message

        # transition to an error state
        @current_state = :errored
      end

      # final state
      # @todo (rhorsey) Why do we need this?
      #
      def run_finished
        logger.info "Running #{__method__}"

        @current_state
      end
      alias_method :final_state, :run_finished

      private

      # Create a state machine from the predefined transitions methods.  This will initialize in the :queued state
      #   and then load in the transitions from the @options hash
      #
      def machine
        logger.info 'Initializing state machine'
        @current_state = :queued

        @transitions = @options[:transitions]
      end

      def next_state
        logger.info "Current state: '#{@current_state}'"
        ns = @transitions.find { |h| h[:from] == @current_state }[:to]
        logger.info "Next state will be: '#{ns}'"

        # Set the next state before calling the method
        @current_state = ns

        # do not return anything, the step method uses the @current_state variable to call run_#{next_state}
      end
    end
  end
end
