#
# Author:: John Keiser (<jkeiser@opscode.com>)
# Copyright:: Copyright (c) 2012 Opscode, Inc.
# License:: Apache License, Version 2.0
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
#

require 'chef/server_api'
require 'chef/chef_fs/file_system/acls_dir'
require 'chef/chef_fs/file_system/base_fs_dir'
require 'chef/chef_fs/file_system/rest_list_dir'
require 'chef/chef_fs/file_system/cookbooks_dir'
require 'chef/chef_fs/file_system/data_bags_dir'
require 'chef/chef_fs/file_system/nodes_dir'
require 'chef/chef_fs/file_system/org_entry'
require 'chef/chef_fs/file_system/organization_invites_entry'
require 'chef/chef_fs/file_system/organization_members_entry'
require 'chef/chef_fs/file_system/policies_dir'
require 'chef/chef_fs/file_system/policy_groups_dir'
require 'chef/chef_fs/file_system/environments_dir'
require 'chef/chef_fs/data_handler/acl_data_handler'
require 'chef/chef_fs/data_handler/client_data_handler'
require 'chef/chef_fs/data_handler/environment_data_handler'
require 'chef/chef_fs/data_handler/node_data_handler'
require 'chef/chef_fs/data_handler/role_data_handler'
require 'chef/chef_fs/data_handler/user_data_handler'
require 'chef/chef_fs/data_handler/group_data_handler'
require 'chef/chef_fs/data_handler/container_data_handler'
require 'chef/chef_fs/data_handler/policy_group_data_handler'

class Chef
  module ChefFS
    module FileSystem
      #
      # Represents the root of a Chef server (or organization), under which
      # nodes, roles, cookbooks, etc. can be found.
      #
      class ChefServerRootDir < BaseFSDir
        #
        # Create a new Chef server root.
        #
        # == Parameters
        #
        # [root_name]
        #   A friendly name for the root, for printing--like "remote" or "chef_central".
        # [chef_config]
        #   A hash with options that look suspiciously like Chef::Config, including the
        #   following keys:
        #   :chef_server_url:: The URL to the Chef server or top of the organization
        #   :node_name:: The username to authenticate to the Chef server with
        #   :client_key:: The private key for the user for authentication
        #   :environment:: The environment in which you are presently working
        #   :repo_mode::
        #     The repository mode, :hosted_everything, :everything or :static.
        #     This determines the set of subdirectories the Chef server will
        #     offer up.
        #   :versioned_cookbooks:: whether or not to include versions in cookbook names
        # [options]
        #   Other options:
        #   :cookbook_version:: when cookbooks are retrieved, grab this version for them.
        #   :freeze:: freeze cookbooks on upload
        #
        def initialize(root_name, chef_config, options = {})
          super("", nil)
          @chef_server_url = chef_config[:chef_server_url]
          @chef_username = chef_config[:node_name]
          @chef_private_key = chef_config[:client_key]
          @environment = chef_config[:environment]
          @repo_mode = chef_config[:repo_mode]
          @versioned_cookbooks = chef_config[:versioned_cookbooks]
          @root_name = root_name
          @cookbook_version = options[:cookbook_version] # Used in knife diff and download for server cookbook version
        end

        attr_reader :chef_server_url
        attr_reader :chef_username
        attr_reader :chef_private_key
        attr_reader :environment
        attr_reader :repo_mode
        attr_reader :cookbook_version
        attr_reader :versioned_cookbooks

        def fs_description
          "Chef server at #{chef_server_url} (user #{chef_username}), repo_mode = #{repo_mode}"
        end

        def rest
          Chef::ServerAPI.new(chef_server_url, :client_name => chef_username, :signing_key_filename => chef_private_key, :raw_output => true, :api_version => "0")
        end

        def get_json(path)
          Chef::ServerAPI.new(chef_server_url, :client_name => chef_username, :signing_key_filename => chef_private_key, :api_version => "0").get(path)
        end

        def chef_rest
          Chef::REST.new(chef_server_url, chef_username, chef_private_key)
        end

        def api_path
          ""
        end

        def path_for_printing
          "#{@root_name}/"
        end

        def can_have_child?(name, is_dir)
          result = children.select { |child| child.name == name }.first
          result && !!result.dir? == !!is_dir
        end

        def org
          @org ||= begin
            path = Pathname.new(URI.parse(chef_server_url).path).cleanpath
            if File.dirname(path) == '/organizations'
              File.basename(path)
            else
              # In Chef 12, everything is in an org.
              'chef'
            end
          end
        end

        def make_child_entry(name)
          children.select { |child| child.name == name }.first
        end

        def children
          @children ||= begin
            result = [
              # /cookbooks
              CookbooksDir.new("cookbooks", self),
              # /data_bags
              DataBagsDir.new("data_bags", self, "data"),
              # /environments
              EnvironmentsDir.new("environments", self, nil, Chef::ChefFS::DataHandler::EnvironmentDataHandler.new),
              # /roles
              RestListDir.new("roles", self, nil, Chef::ChefFS::DataHandler::RoleDataHandler.new)
            ]
            if repo_mode == 'hosted_everything'
              result += [
                # /acls
                AclsDir.new("acls", self),
                # /clients
                RestListDir.new("clients", self, nil, Chef::ChefFS::DataHandler::ClientDataHandler.new),
                # /containers
                RestListDir.new("containers", self, nil, Chef::ChefFS::DataHandler::ContainerDataHandler.new),
                # /groups
                RestListDir.new("groups", self, nil, Chef::ChefFS::DataHandler::GroupDataHandler.new),
                # /nodes
                NodesDir.new("nodes", self, nil, Chef::ChefFS::DataHandler::NodeDataHandler.new),
                # /org.json
                OrgEntry.new("org.json", self),
                # /members.json
                OrganizationMembersEntry.new("members.json", self),
                # /invitations.json
                OrganizationInvitesEntry.new("invitations.json", self),
                # /policies
                PoliciesDir.new("policies", self, nil, Chef::ChefFS::DataHandler::PolicyDataHandler.new),
                # /policy_groups
                PolicyGroupsDir.new("policy_groups", self, nil, Chef::ChefFS::DataHandler::PolicyGroupDataHandler.new),
              ]
            elsif repo_mode != 'static'
              result += [
                # /clients
                RestListDir.new("clients", self, nil, Chef::ChefFS::DataHandler::ClientDataHandler.new),
                # /nodes
                NodesDir.new("nodes", self, nil, Chef::ChefFS::DataHandler::NodeDataHandler.new),
                # /users
                RestListDir.new("users", self, nil, Chef::ChefFS::DataHandler::UserDataHandler.new)
              ]
            end
            result.sort_by { |child| child.name }
          end
        end
      end
    end
  end
end
