# HomeLab Setup

Welcome to my HomeLab repository! This space is dedicated to documenting the setup and automatic build/rebuild processes of my personal HomeLab. The primary goal is to enable anyone (including my future self) to check out this repository, create the necessary `.env` file, and have everything up and running smoothly with minimal manual intervention.

## Objective

The aim of this HomeLab is to create a robust, scalable, and automated environment that supports my networking, storage, and computing needs. By leveraging infrastructure as code (IaC) and automation tools, I strive to achieve a setup that's easy to manage, replicate, and update.

## Hardware Overview

My HomeLab is built on a variety of hardware to support different functions, from networking to storage and computing.

- **Network Gear**: UniFi Switches and Security Gateways for reliable and manageable network infrastructure.
- **NAS**: Synology unit serving as centralized storage solution for backups, media, and personal files.
- **Raspberry Pi's**: Used for lightweight computing tasks, IoT projects, and as kubernetes hosts.
- **Dell Optiplexes**: Used kubernetes hosts.
- **Dell Precision**: High-performance workstation for intensive computing tasks, virtualization, and AI projects.

## Infrastructure Software

The backbone of the HomeLab is supported by several key software solutions that facilitate containerization, orchestration, and automation.

- **Docker**: Containerization platform for building, deploying, and managing containerized applications.
- **Portainer**: GUI for managing Docker/Kubernetes environments, simplifying container deployment and monitoring.
- **Kubernetes**: Container orchestration system for automating application deployment, scaling, and management.
- **Ansible**: Automation tool for provisioning, configuration management, and application deployment.

## HomeLab Software

For home automation and various HomeLab projects, the following software plays a crucial role:

- **Home Assistant**: Open-source home automation platform that enables control over smart devices, with automation rules and energy monitoring features.
