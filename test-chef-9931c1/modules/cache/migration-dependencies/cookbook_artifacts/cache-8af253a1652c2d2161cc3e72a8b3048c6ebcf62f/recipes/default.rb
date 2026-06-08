# Include memcached
include_recipe 'memcached'

# Configure Redis with authentication
node.default['redisio']['servers'] = [
  {
    'port' => '6379',
    'requirepass' => 'redis_secure_password_123',
    'replicaservestaledata' => nil,
  }
]

# Create Redis log directory
directory '/var/log/redis' do
  owner 'redis'
  group 'redis'
  mode '0755'
  recursive true
end

# Include redis
include_recipe 'redisio'

# HACK
ruby_block "fix_redis_config" do
  block do
    config_file = "/etc/redis/6379.conf"
    if File.exist?(config_file)
      content = File.read(config_file)
      content.gsub!(/^replica-serve-stale-data.*$/, '')
      content.gsub!(/^replica-read-only.*$/, '')
      content.gsub!(/^repl-ping-replica-period.*$/, '')
      content.gsub!(/^client-output-buffer-limit.*$/, '')
      content.gsub!(/^replica-priority.*$/, '')
      File.write(config_file, content)
    end
  end
end

include_recipe 'redisio::enable'
