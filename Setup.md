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

## install requirements
pip install -r requirements.txt

## Clone K3s Ansible Repo
git clone https://github.com/techno-tim/k3s-ansible.git



