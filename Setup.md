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


setup.sh


# Test your cluster with:
export KUBECONFIG=/home/K3S_USERNAME/.kube/config
kubectl config use-context K3S_CONTEXT
kubectl get node -o wide
