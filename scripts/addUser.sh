#!/bin/bash

# Simple script to add a new user to TAK server

color() {
    STARTCOLOR="\e[$2";
    ENDCOLOR="\e[0m";
    export "$1"="$STARTCOLOR%b$ENDCOLOR" 
}
color info 96m
color success 92m 
color warning 93m 
color danger 91m 

DOCKER_COMPOSE="docker-compose"

if ! command -v docker-compose
then
	DOCKER_COMPOSE="docker compose"
fi

if [ -z "$1" ];
then
	printf $danger "Usage: ./addUser.sh <username> [password] [--admin] [--no-cert-package]\n"
	printf $info "Example: ./addUser.sh newuser\n"
	printf $info "Example: ./addUser.sh newuser mypassword\n"
	printf $info "Example: ./addUser.sh newuser mypassword --admin\n"
	printf $info "Example: ./addUser.sh newuser mypassword --admin --no-cert-package\n"
	exit 1
fi

USERNAME=$1
CREATE_DP=true
CREATE_ADMIN=false

# Check if password is provided
if [ -n "$2" ] && [ "$2" != "--admin" ] && [ "$2" != "--no-cert-package" ];
then
	password=$2
else
	# Generate random password
	pwd=$(cat /dev/urandom | tr -dc '[:alpha:][:digit:]' | fold -w ${1:-11} | head -n 1)
	password=$pwd"DRN1!"
fi

# Check for flags
for arg in "$@"; do
	if [ "$arg" == "--admin" ];
	then
		CREATE_ADMIN=true
	fi
	if [ "$arg" == "--no-cert-package" ];
	then
		CREATE_DP=false
	fi
done

printf $success "\n=== Creating TAK Server User ===\n"
printf $info "Username: $USERNAME\n"
printf $info "Password: $password\n"
printf $warning "\nMake a note of the password. It won't be shown again.\n\n"

# Get HOSTNAME/IP from .env or use current IP
if [ -f ".env" ];
then
	source .env
	if [ -n "$HOSTNAME" ];
	then
		ACCESS_HOST=$HOSTNAME
	fi
fi

if [ -z "$ACCESS_HOST" ];
then
	# Try to get it from tak/CoreConfig.xml
	ACCESS_HOST=$(grep -oP 'HOSTIP' tak/CoreConfig.xml | head -1 || echo "localhost")
fi

# Create client certificate
printf $info "\nCreating certificate for $USERNAME...\n"
$DOCKER_COMPOSE exec tak bash -c "cd /opt/tak/certs && ./makeCert.sh client $USERNAME"
if [ $? -ne 0 ];
then
	printf $danger "Failed to create certificate\n"
	exit 1
fi

# Add user to TAK database
printf $info "Adding user to TAK database...\n"
$DOCKER_COMPOSE exec tak bash -c "cd /opt/tak/ && java -jar /opt/tak/utils/UserManager.jar usermod -A -p '$password' $USERNAME"
if [ $? -ne 0 ];
then
	printf $danger "Failed to add user to database\n"
	exit 1
fi

# Add certificate to user
printf $info "Linking certificate to user...\n"
$DOCKER_COMPOSE exec tak bash -c "cd /opt/tak/ && java -jar utils/UserManager.jar certmod -A certs/files/$USERNAME.pem"
if [ $? -ne 0 ];
then
	printf $danger "Failed to link certificate\n"
	exit 1
fi

# Assign roles
printf $info "Assigning roles...\n"
# Always add ROLE_USER
$DOCKER_COMPOSE exec tak bash -c "cd /opt/tak/ && java -jar utils/UserManager.jar moduser $USERNAME ROLE_USER"
if [ $? -ne 0 ];
then
	printf $danger "Failed to assign ROLE_USER\n"
	exit 1
fi

# Add ROLE_ADMIN if requested
if [ "$CREATE_ADMIN" = true ];
then
	$DOCKER_COMPOSE exec tak bash -c "cd /opt/tak/ && java -jar utils/UserManager.jar moduser $USERNAME ROLE_ADMIN"
	if [ $? -ne 0 ];
	then
		printf $danger "Failed to assign ROLE_ADMIN\n"
		exit 1
	fi
fi

# Set permissions
$DOCKER_COMPOSE exec tak bash -c "chown -R 1000:1000 /opt/tak/certs/"

# Create certificate data package if requested
if [ "$CREATE_DP" = true ];
then
	printf $info "Creating certificate data package...\n"
	./scripts/certDP.sh $ACCESS_HOST $USERNAME
fi

printf $success "\n=== User Created Successfully ===\n"
printf $success "Username: $USERNAME\n"
printf $success "Password: $password\n"
if [ "$CREATE_ADMIN" = true ];
then
	printf $success "Roles: ROLE_USER, ROLE_ADMIN\n"
else
	printf $success "Roles: ROLE_USER\n"
fi
printf $info "Certificate: tak/certs/files/$USERNAME.p12\n"
if [ "$CREATE_DP" = true ];
then
	printf $info "Data Package: tak/certs/files/$USERNAME-$ACCESS_HOST.dp.zip\n"
fi
printf $success "\nUser is ready to login!\n\n"
