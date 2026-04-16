# Getting Started setting up HomeLab

## clone the repo
git clone https://github.com/tmalsdorf/MyHomeLab.git

## create your venv
python3 -m venv venv

## activate your venv
source venv/bin/activate

## create your inventory file 
copy the env file from the example.env
cp example.env .env

## Edit .env with your configuration
Edit the `.env` file to set your cluster IPs and options:
- For single environment: Set `ENVIRONMENT=dev|uat|prod`
- For all environments: Set `SETUP_ALL_ENVIRONMENTS=true`

## install requirements
pip install -r requirements.txt

## install ansible collections
ansible-galaxy collection install -r collections/requirements.yml

## run the setup script
./setup.sh

## Multi-Environment Setup

To set up all three environments (dev, uat, prod) in one run:

1. Edit `.env` and set:
   ```
   SETUP_ALL_ENVIRONMENTS=true
   K3S_ENABLED_DEV=true
   K3S_MASTERS_DEV="192.168.3.50"
   K3S_NODES_DEV="192.168.3.51,192.168.3.52"
   # ... configure uat and prod similarly
   ```

2. Run `./setup.sh` - this will create all three inventory files

3. To deploy a specific environment:
   ```bash
   ENVIRONMENT=dev ./setup.sh
   ENVIRONMENT=uat ./setup.sh
   ENVIRONMENT=prod ./setup.sh
   ```

