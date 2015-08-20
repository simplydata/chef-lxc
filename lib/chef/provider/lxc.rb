require 'chef/lxc_helper'

class Chef
  class Provider
    class Lxc < Chef::Provider
      include Chef::LXCHelper

      attr_reader :ct

      def initialize(new_resource, run_context)
        super(new_resource, run_context)
      end

      def whyrun_supported?
        true
      end

      def load_current_resource
        config_path = new_resource.config_path || ::LXC.global_config_item('lxc.lxcpath')
        @ct = ::LXC::Container.new(new_resource.container_name, config_path)
      end

      def action_create
        unless ct.defined?
          converge_by("create container '#{ct.name}'") do
            template = new_resource.lxc_template.type
            template_options = new_resource.lxc_template.options
            flags = 0
            ct.create(
              new_resource.lxc_template.type,
              new_resource.block_device,
              new_resource.bdev_specs,
              new_resource.flags,
              new_resource.lxc_template.options
            )
            update_config
          end
        end
      end

      def update_config
        updated_items = []
        new_resource.config.each do |key, expected_value|
          if ct.config_item(key) != expected_value
            ct.set_config_item(key, expected_value)
            updated_items << key
          end
        end
        unless updated_items.empty?
          ct.save_config
        end
      end

      def action_stop
        if ct.running?
          converge_by("stop container '#{ct.name}'") do
            ct.stop
          end
        end
      end

      def action_reboot
        converge_by("reboot container '#{ct.name}'") do
          ct.reboot
        end
      end

      def action_start
        unless ct.running?
          converge_by("start container '#{ct.name}'") do
            ct.start
            if new_resource.wait_for_network
              until ct.ip_addresses.empty?
                Chef::Log.debug('waiting for ip allocation')
                sleep 1
              end
            end
          end
        end
        unless new_resource.recipe_block.nil?
          recipe_in_container(ct, &new_resource.recipe_block)
        end
      end

      def action_destroy
        if ct.defined?
          converge_by("destroy container '#{ct.name}'") do
            ct.destroy
          end
        end
      end
    end
  end
end
