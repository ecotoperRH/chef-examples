# Install Python 3 and required system packages
package ['python3', 'python3-pip', 'python3-venv', 'git', 'postgresql', 'postgresql-contrib', 'libpq-dev']

# Create application directory
directory '/opt/fastapi-tutorial' do
  owner 'root'
  group 'root'
  mode '0755'
  recursive true
end

# Clone FastAPI tutorial repository
git '/opt/fastapi-tutorial' do
  repository 'https://github.com/dibanez/fastapi_tutorial.git'
  revision 'main'
  action :sync
end

# Create Python virtual environment
execute 'create_venv' do
  command 'python3 -m venv /opt/fastapi-tutorial/venv'
  creates '/opt/fastapi-tutorial/venv'
end

# Install Python dependencies
execute 'install_dependencies' do
  command '/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt'
  cwd '/opt/fastapi-tutorial'
  action :run
end

# Configure PostgreSQL service
service 'postgresql' do
  action [:enable, :start]
end

# Create database and user
execute 'create_db_user' do
  command <<-EOH
    sudo -u postgres psql -c "CREATE USER fastapi WITH PASSWORD 'fastapi_password';" || true
    sudo -u postgres psql -c "CREATE DATABASE fastapi_db OWNER fastapi;" || true
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi;" || true
  EOH
  action :run
end

# Create environment configuration file
file '/opt/fastapi-tutorial/.env' do
  content <<-ENV
PROJECT_NAME="FastAPI Tutorial"
API_VERSION=1.0.0
DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
  ENV
  mode '0644'
  owner 'root'
  group 'root'
end

# Create systemd service file
file '/etc/systemd/system/fastapi-tutorial.service' do
  content <<-SERVICE
[Unit]
Description=FastAPI Tutorial Service
After=network.target postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/fastapi-tutorial
Environment="PATH=/opt/fastapi-tutorial/venv/bin"
ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
  SERVICE
  mode '0644'
  owner 'root'
  group 'root'
  notifies :run, 'execute[systemd_reload]', :immediately
end

# Reload systemd
execute 'systemd_reload' do
  command 'systemctl daemon-reload'
  action :nothing
end

# Enable and start the service
service 'fastapi-tutorial' do
  action [:enable, :start]
end
