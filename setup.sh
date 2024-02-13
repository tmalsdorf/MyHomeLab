#!/bin/bash

# Source the .env file if it exists
if [ -f .env ]; then
    source .env
    echo ".env file exists and sourced."
else
    echo ".env file does not exist. Creating from example..."
    # Create .env file from example
    cp example.env .env
    echo ".env file created from example."
    echo "Please edit the .env file and run the script again."
    exit 0  # Exit script if .env was just created from example
fi

# Check if already in the repository directory
if [ -d "$REPO_NAME/.git" ]; then
    echo "Already in the repository directory."
    cd $REPO_NAME
elif [ "$(basename "$(pwd)")" = "$REPO_NAME" ]; then
    echo "Already in the repository directory."
else
    echo "Not in the repository directory. Cloning..."
    # Clone your GitHub repository
    git clone https://github.com/$GITHUB_USERNAME/$REPO_NAME.git
    cd $REPO_NAME
fi

# Check if virtual environment exists
if [ -d "venv" ]; then
    echo "Virtual environment already exists."
else
    # Create a Python virtual environment
    python3 -m venv venv
fi

## activate your venv
echo "Activating virtual environment..."
source venv/bin/activate

## install requirements
echo "Installing requirements..."
pip install -r requirements.txt


if [ "$K3S_ENABLED" = true ]; then
    echo "K3s is enabled."
    ## Clone K3s Ansible Repo
    echo "Cloning K3s Ansible Repo..."
    git clone https://github.com/techno-tim/k3s-ansible.git  # Additional actions for configuring K3s can be added here
else
    echo "K3s is not enabled."
fi

if [ "$SYNOLOGY_ENABLED" = true ]; then
    echo "Synology is enabled."
    # Additional actions for configuring Synology can be added here
else
    echo "Synology is not enabled."
fi

if [ "$DOCKER_SERVER_ENABLED" = true ]; then
    echo "Docker server is enabled."
    # Additional actions for configuring Docker server can be added here
    if [ -n "$DOCKER_IMAGES" ]; then
        echo "Running Docker images: $DOCKER_IMAGES"
        # Run Docker images listed in DOCKER_IMAGES
        for image in $DOCKER_IMAGES; do
            docker run -d $image
        done
    else
        echo "No Docker images specified to run."
    fi
else
    echo "Docker server is not enabled."
fi