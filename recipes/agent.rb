package 'docker.io'

agent_username = node['ros_buildfarm']['agent']['agent_username']
agent_homedir = "/home/#{agent_username}"

user agent_username do
  manage_home true
  comment 'Jenkins Agent User'
end

# Add agent user to the docker group to allow them to build and run docker
# containers.
group 'docker' do
  append true
  members [agent_username]
  action :manage # Group should be created by docker package.
end

data_bag('ros_buildfarm_host_keys').each do |hostkey|
  hostkey_info = data_bag_item('ros_buildfarm_host_keys', hostkey)
  ssh_known_hosts_entry hostkey_info['host'] do
    key hostkey_info['key']
    key_type hostkey_info['key_type']
  end
end

package 'openjdk-8-jdk-headless'

swarm_client_version = node['ros_buildfarm']['jenkins']['plugins']['swarm']
swarm_client_url = "https://repo.jenkins-ci.org/releases/org/jenkins-ci/plugins/swarm-client/#{swarm_client_version}/swarm-client-#{swarm_client_version}.jar"
swarm_client_jarfile_path = "/home/#{agent_username}/swarm-client-#{swarm_client_version}.jar"

# Download swarm client program from url and install it to the jenkins-agent user's home directory.
remote_file swarm_client_jarfile_path do
  source swarm_client_url
  owner agent_username
  group agent_username
  mode '0444'
end

package 'python3-empy'

directory "/home/#{agent_username}/.ccache" do
  group agent_username
  owner agent_username
end

# Install version control utilities
%w[bzr git mercurial subversion].each do |vcspkg|
  package vcspkg
end

# TODO install this only on amd64?
package 'qemu-user-static'
template '/etc/default/jenkins-agent' do
  source 'jenkins-agent.env.erb'
  variables Hash[
    java_args: node['ros_buildfarm']['agent']['java_args'],
    jarfile: swarm_client_jarfile_path,
    jenkins_url: node['ros_buildfarm']['jenkins_url'],
    username: node['ros_buildfarm']['agent']['username'],
    password: node['ros_buildfarm']['agent']['password'],
    name: node['ros_buildfarm']['agent']['nodename'],
    description: node['ros_buildfarm']['agent']['description'],
    executors: node['ros_buildfarm']['agent']['executors'],
    user_home: agent_homedir,
    labels: node['ros_buildfarm']['agent']['labels'],
  ]

end

template '/etc/systemd/system/jenkins-agent.service' do
  source 'jenkins-agent.service.erb'
  variables Hash[
    service_name: 'jenkins-agent',
    username: agent_username,
  ]
  notifies :run, 'execute[systemctl-daemon-reload]', :immediately
end

execute 'systemctl-daemon-reload' do
  command 'systemctl daemon-reload'
  action :nothing
end

service 'jenkins-agent' do
  action [:start, :enable]
end
