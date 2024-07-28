#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = FitFile_spec.rb -- Fit4Ruby - FIT file processing library for Ruby
#
# Copyright (c) 2014, 2015, 2020 by Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

$:.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))

#require "super_diff/rspec"
require 'fit4ruby'

ENV['TZ'] = 'UTC'

describe Fit4Ruby do
  before(:each) do
    File.delete(fit_file) if File.exist?(fit_file)
    expect(File.exist?(fit_file)).to be false
  end

  after(:each) { File.delete(fit_file) }

  let(:fit_file) { 'test.fit' }
  # Round the timestamp to seconds. This is what the file format can store. A
  # higher resolution would create errors during comparions.
  let(:timestamp) { Time.at(Time.now.to_i) }
  let(:user_data) do
    {
      :age => 33, :height => 1.78, :weight => 73.0,
      :gender => 'male', :activity_class => 4.0,
      :max_hr => 178
    }
  end
  let(:user_profile) do
    {
      :friendly_name => 'Fast Runner',
      :gender => 'male',
      :age => 33,
      :height => 1.78,
      :weight => 73.0,
      :resting_heart_rate => 43
    }
  end
  def device_info_fenix3(ts)
    {
      :timestamp => ts,
      :device_index => 0, :manufacturer => 'garmin',
      :garmin_product => 'fenix3',
      :serial_number => 123456789
    }
  end
  def device_info_fenix3_gps(ts)
    {
      :timestamp => ts,
      :device_index => 1, :manufacturer => 'garmin',
      :garmin_product => 'fenix3_gps'
    }
  end
  def device_info_hrm_run(ts, bs = 'ok')
    {
      :timestamp => ts,
      :device_index => 2, :manufacturer => 'garmin',
      :garmin_product => 'hrm_run',
      :battery_status => bs
    }
  end
  def device_info_sdm4(ts)
    {
      :timestamp => timestamp,
      :device_index => 3, :manufacturer => 'garmin',
      :garmin_product => 'sdm4',
      :battery_status => 'ok'
    }
  end

  context 'running activity' do
    let(:activity) do
      ts = timestamp
      a = Fit4Ruby::Activity.new
      a.total_timer_time = 30 * 60.0
      a.new_user_data(user_data)
      a.new_user_profile(user_profile)

      a.new_event({ :event => 'timer', :event_type => 'start_time' })
      a.new_device_info(device_info_fenix3(ts))
      a.new_device_info(device_info_fenix3_gps(ts))
      a.new_device_info(device_info_hrm_run(ts))
      a.new_device_info(device_info_sdm4(ts))
      a.new_data_sources({ :timestamp => ts, :distance => 1,
                           :speed => 1, :cadence => 3, :elevation => 1,
                           :heart_rate => 2 })
      laps = 0
      0.upto(a.total_timer_time / 60) do |mins|
        ts += 60
        a.new_record({
          :timestamp => ts,
          :position_lat => 51.5512 - mins * 0.0008,
          :position_long => 11.647 + mins * 0.002,
          :distance => 200.0 * mins,
          :altitude => (100 + mins * 0.5).to_i,
          :speed => 3.1,
          :vertical_oscillation => 9 + mins * 0.02,
          :stance_time => 235.0 * mins * 0.01,
          :stance_time_percent => 32.0,
          :heart_rate => 140 + mins,
          :cadence => 75,
          :activity_type => 'running',
          :fractional_cadence => (mins % 2) / 2.0
        })

        if mins > 0 && mins % 5 == 0
          a.new_lap({ :timestamp => ts, :sport => 'running',
                      :message_index => laps, :total_cycles => 195 })
          laps += 1
        end
      end
      a.new_session({ :timestamp => ts, :sport => 'running' })
      a.new_event({ :timestamp => ts, :event => 'recovery_time',
                    :event_type => 'marker',
                    :recovery_time => 2160 })
      a.new_event({ :timestamp => ts, :event => 'vo2max',
                    :event_type => 'marker', :vo2max => 52 })
      a.new_event({ :timestamp => ts, :event => 'timer',
                    :event_type => 'stop_all' })
      ts += 1
      a.new_device_info(device_info_fenix3(ts))
      a.new_device_info(device_info_fenix3_gps(ts))
      a.new_device_info(device_info_hrm_run(ts, 'low'))
      a.new_device_info(device_info_sdm4(ts))
      ts += 120
      a.new_event({ :timestamp => ts, :event => 'recovery_hr',
                    :event_type => 'marker', :recovery_hr => 132 })

      a.aggregate
      a
    end

    it 'should write an Activity FIT file and read it back' do
      Fit4Ruby.write(fit_file, activity)
      expect(File.exist?(fit_file)).to be true

      b = Fit4Ruby.read(fit_file)
      expect(b.laps.count).to eq 6
      expect(b.lengths.count).to eq 0
      expect(b.records.first.get('position_lat')).to be_within(0.001).of(51.551)
      expect(b.records.first.get('position_long')).to be_within(0.001).of(11.647)
      expect(b.export).to eq(activity.export)
    end

  end

  context 'swimming activity' do
    let(:activity) do
      ts = timestamp
      laps = 0
      lengths = 0
      a = Fit4Ruby::Activity.new

      a.total_timer_time = 30 * 60.0
      a.new_device_info(device_info_fenix3(ts))

      0.upto(a.total_timer_time / 60) do |mins|
        ts += 60
        if mins > 0 && mins % 5 == 0
          a.new_lap({ :timestamp => ts, :sport => 'swimming',
            :message_index => laps, :total_cycles => 195 })
          laps += 1

          a.new_length({ :timestamp => ts, :event => 'length',
            :message_index => lengths, :total_strokes => 45 })
          lengths += 1
        end
      end
      a.aggregate
      a
    end

    it 'should write an Activity FIT file and read it back' do
      Fit4Ruby.write(fit_file, activity)
      expect(File.exist?(fit_file)).to be true

      b = Fit4Ruby.read(fit_file)
      expect(b.laps.count).to eq 6
      expect(b.lengths.count).to eq 6
      expect(b.laps.select { |l| l.sport == 'swimming' }.count).to eq 6
      expect(b.lengths.select { |l| l.total_strokes == 45 }.count).to eq 6
      expect(b.export).to eq(activity.export)
    end

  end

  context 'activity with developer fields' do
    let(:activity) do
      ts = timestamp
      laps = 0
      lengths = 0
      a = Fit4Ruby::Activity.new

      a.total_timer_time = 30 * 60.0
      a.new_device_info(device_info_fenix3(ts))
      a.new_developer_data_id({
        application_id: [ 24, 251, 44, 240, 26, 75, 67, 13,
                          173, 102, 152, 140, 132, 116, 33, 244 ],
        application_version: 77
      })
      a.new_field_description({
        developer_data_index: 0,
        field_definition_number: 0,
        fit_base_type_id: 132,
        field_name: 'Power',
        units: 'Watts',
        native_mesg_num: 20,
        native_field_num: 7
      })
      a.new_data_sources({ :timestamp => ts, :distance => 1,
                           :speed => 1, :cadence => 3, :elevation => 1,
                           :heart_rate => 2 })
      laps = 0
      0.upto(a.total_timer_time / 60) do |mins|
        ts += 60
        a.new_record({
          :timestamp => ts,
          :position_lat => 51.5512 - mins * 0.0008,
          :position_long => 11.647 + mins * 0.002,
          :distance => 200.0 * mins,
          :altitude => (100 + mins * 0.5).to_i,
          :speed => 3.1,
          :vertical_oscillation => 9 + mins * 0.02,
          :stance_time => 235.0 * mins * 0.01,
          :stance_time_percent => 32.0,
          :heart_rate => 140 + mins,
          :cadence => 75,
          :activity_type => 'running',
          :fractional_cadence => (mins % 2) / 2.0,
          :Power_18FB2CF01A4B430DAD66988C847421F4 => 240
        })

        if mins > 0 && mins % 5 == 0
          a.new_lap({ :timestamp => ts, :sport => 'running',
                      :message_index => laps, :total_cycles => 195 })
          laps += 1
        end
      end
      a.aggregate
      a
    end

    it 'should write an Activity FIT file and read it back' do
      Fit4Ruby.write(fit_file, activity)
      expect(File.exist?(fit_file)).to be true

      # This currently does not work as the saving of developer fields is not
      # yet implemented.
      #b = Fit4Ruby.read(fit_file)
      #expect(b.export).to eq(activity.export)
    end
  end

end

