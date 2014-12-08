require 'rspec'
require 'spec_helper'

describe TimeLogger do


  describe 'single value' do
    before :all do
      @t = TimeLogger.new
    end

    it 'should create an instance' do
      expect(@t).not_to be nil
    end

    it 'should log time' do
      @t.start('test')
      expect(@t.channels['test']).not_to eq nil

      puts @t.inspect
      sleep 1
      @t.stop('test')

      expect(@t.channels['test']).to eq nil
      puts @t.inspect
    end

    it 'should report time' do
      expect(@t.delta('test').first.key?('test')).to eq true
      time_hash = @t.delta('test').first
      puts time_hash
      expect(time_hash['test']).to be_within(0.1).of(1)
    end
  end

  describe 'multiple values' do
    before :all do
      @t = TimeLogger.new
    end

    it 'should log multiple times' do
      @t.start('log channel with spaces')
      sleep 1
      @t.start('second_channel')
      @t.start('third channel')
      sleep 1
      @t.stop_all

      r = @t.report
      expect(r).to be_an Array
      expect(r.first[:delta]).to be_within(0.1).of(2)
      expect(r.last[:delta]).to be_within(0.1).of(1)
      puts @t.report
    end

    it 'should save a file' do
      #@t.save("#{File.dirname()}"
    end
  end
end
