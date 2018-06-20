# Copyright 2013 Google Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
require File.expand_path("../../base", __FILE__)

require "vagrant-google/config"

describe VagrantPlugins::Google::Config do
  let(:instance) { described_class.new }

  # Ensure tests are not affected by Google credential environment variables
  before :each do
    allow(ENV).to receive_messages(:[] => nil)
  end

  describe "defaults" do
    subject do
      instance.tap do |o|
        o.finalize!
      end
    end

    its("name")                   { should match "i-[0-9]{10}-[0-9a-f]{4}" }
    its("image")                  { should be_nil }
    its("image_family")           { should be_nil }
    its("image_project_id")       { should be_nil }
    its("instance_group")         { should be_nil }
    its("zone")                   { should == "us-central1-f" }
    its("network")                { should == "default" }
    its("machine_type")           { should == "n1-standard-1" }
    its("disk_size")              { should == 10 }
    its("disk_name")              { should be_nil }
    its("disk_type")              { should == "pd-standard" }
    its("instance_ready_timeout") { should == 20 }
    its("metadata")               { should == {} }
    its("tags")                   { should == [] }
    its("labels")                 { should == {} }
    its("scopes")                 { should == nil }
    its("preemptible")            { should be_falsey }
    its("auto_restart")           { should }
    its("on_host_maintenance")    { should == "MIGRATE" }
  end

  describe "overriding defaults" do
    # I typically don't meta-program in tests, but this is a very
    # simple boilerplate test, so I cut corners here. It just sets
    # each of these attributes to "foo" in isolation, and reads the value
    # and asserts the proper result comes back out.
    [:name, :image, :image_family, :image_project_id, :zone, :instance_ready_timeout, :machine_type, :disk_size, :disk_name, :disk_type,
     :network, :network_project_id, :metadata, :labels, :can_ip_forward, :external_ip, :autodelete_disk].each do |attribute|

      it "should not default #{attribute} if overridden" do
        instance.send("#{attribute}=".to_sym, "foo")
        instance.finalize!
        expect(instance.send(attribute)).to eq "foo"
      end
    end

    it "should raise error when preemptible and auto_restart is true" do
      instance.preemptible = true
      instance.auto_restart = true
      instance.finalize!
      errors = instance.validate("foo")["Google Provider"]
      expect(errors).to include(/auto_restart_invalid_on_preemptible/)
    end

    it "should raise error when preemptible and on_host_maintenance is not TERMINATE" do
      instance.preemptible = true
      instance.on_host_maintenance = "MIGRATE"
      instance.finalize!
      errors = instance.validate("foo")["Google Provider"]
      expect(errors).to include(/on_host_maintenance_invalid_on_preemptible/)
    end
  end

  describe "getting credentials from environment" do
    context "without Google credential environment variables" do
      subject do
        instance.tap do |o|
          o.finalize!
        end
      end

      its("google_client_email") { should be_nil }
      its("google_json_key_location") { should be_nil }
    end

    context "with Google credential environment variables" do
      before :each do
        allow(ENV).to receive(:[]).with("GOOGLE_CLIENT_EMAIL").and_return("client_id_email")
        allow(ENV).to receive(:[]).with("GOOGLE_JSON_KEY_LOCATION").and_return("/path/to/json/key")
      end

      subject do
        instance.tap do |o|
          o.finalize!
        end
      end

      its("google_client_email") { should == "client_id_email" }
      its("google_json_key_location") { should == "/path/to/json/key" }
    end

    context "With none of the Google credential environment variables set" do
      before :each do
        allow(ENV).to receive(:[]).with("GOOGLE_CLIENT_EMAIL").and_return("client_id_email")
      end

      it "Should return no key set errors" do
        instance.finalize!
        expect(instance.validate("foo")["Google Provider"][1]).to include("en.vagrant_google.config.google_key_location_required")
      end
    end
  end

  describe "zone config" do
    let(:config_image)           { "foo" }
    let(:config_machine_type)    { "foo" }
    let(:config_disk_size)       { 99 }
    let(:config_disk_name)       { "foo" }
    let(:config_disk_type)       { "foo" }
    let(:config_name)            { "foo" }
    let(:config_zone)            { "foo" }
    let(:config_network)         { "foo" }
    let(:can_ip_forward)         { true }
    let(:external_ip)            { "foo" }
    let(:internal_ip)            { "foo" }

    def set_test_values(instance)
      instance.name              = config_name
      instance.network           = config_network
      instance.image             = config_image
      instance.machine_type      = config_machine_type
      instance.disk_size         = config_disk_size
      instance.disk_name         = config_disk_name
      instance.disk_type         = config_disk_type
      instance.zone              = config_zone
      instance.can_ip_forward    = can_ip_forward
      instance.external_ip       = external_ip
      instance.internal_ip       = internal_ip
    end

    it "should raise an exception if not finalized" do
      expect { instance.get_zone_config("us-central1-f") }
        .to raise_error(RuntimeError,/Configuration must be finalized/)
    end

    context "with no specific config set" do
      subject do
        # Set the values on the top-level object
        set_test_values(instance)

        # Finalize so we can get the zone config
        instance.finalize!

        # Get a lower level zone
        instance.get_zone_config("us-central1-f")
      end

      its("name")              { should == config_name }
      its("image")             { should == config_image }
      its("machine_type")      { should == config_machine_type }
      its("disk_size")         { should == config_disk_size }
      its("disk_name")         { should == config_disk_name }
      its("disk_type")         { should == config_disk_type }
      its("network")           { should == config_network }
      its("zone")              { should == config_zone }
      its("can_ip_forward")    { should == can_ip_forward }
      its("external_ip")       { should == external_ip }
    end

    context "with a specific config set" do
      let(:zone_name) { "hashi-zone" }

      subject do
        # Set the values on a specific zone
        instance.zone_config zone_name do |config|
          set_test_values(config)
        end

        # Finalize so we can get the zone config
        instance.finalize!

        # Get the zone
        instance.get_zone_config(zone_name)
      end

      its("name")              { should == config_name }
      its("image")             { should == config_image }
      its("machine_type")      { should == config_machine_type }
      its("disk_size")         { should == config_disk_size }
      its("disk_name")         { should == config_disk_name }
      its("disk_type")         { should == config_disk_type }
      its("network")           { should == config_network }
      its("zone")              { should == zone_name }
      its("can_ip_forward")    { should == can_ip_forward }
      its("external_ip")       { should == external_ip }
    end

    describe "inheritance of parent config" do
      let(:zone) { "hashi-zone" }

      subject do
        # Set the values on a specific zone
        instance.zone_config zone do |config|
          config.image = "child"
        end

        # Set some top-level values
        instance.image = "parent"

        # Finalize and get the zone
        instance.finalize!
        instance.get_zone_config(zone)
      end

      its("image") { should == "child" }
    end

    describe "shortcut configuration" do
      subject do
        # Use the shortcut configuration to set some values
        instance.zone_config "us-central1-f", :image => "child"
        instance.finalize!
        instance.get_zone_config("us-central1-f")
      end

      its("image") { should == "child" }
    end

    describe "merging" do
      let(:first) { described_class.new }
      let(:second) { described_class.new }

      it "should merge the metadata" do
        first.metadata["one"] = "foo"
        second.metadata["two"] = "bar"

        third = first.merge(second)
        expect(third.metadata).to eq({
          "one" => "foo",
          "two" => "bar"
        })
      end
    end

    describe "zone_preemptible" do
      let(:zone) { "hashi-zone" }
      subject do
        instance.zone = zone
        instance.zone_config zone do |config|
          config.preemptible = true
          config.auto_restart = true
          config.on_host_maintenance = "MIGRATE"
        end

        instance.tap do |o|
          o.finalize!
        end
      end

      before :each do
        # Stub out required env to make sure we produce only errors we're looking for.
        allow(ENV).to receive(:[]).with("GOOGLE_CLIENT_EMAIL").and_return("client_id_email")
        allow(ENV).to receive(:[]).with("GOOGLE_PROJECT_ID").and_return("my-awesome-project")
        allow(ENV).to receive(:[]).with("GOOGLE_JSON_KEY_LOCATION").and_return("/path/to/json/key")
        allow(ENV).to receive(:[]).with("GOOGLE_SSH_KEY_LOCATION").and_return("/path/to/ssh/key")
        allow(File).to receive(:exist?).with("/path/to/json/key").and_return(true)
      end

      it "should fail auto_restart validation" do
        instance.finalize!
        errors = subject.validate("foo")["Google Provider"]
        expect(errors).to include(/auto_restart_invalid_on_preemptible/)
      end

      it "should fail on_host_maintenance validation" do
        instance.finalize!
        errors = subject.validate("foo")["Google Provider"]
        expect(errors).to include(/on_host_maintenance_invalid_on_preemptible/)
      end
    end
  end
end
