#!/usr/bin/env bash

#=======================================================================#
# Copyright (C) 2020 - 2022 Dominik Willner <th33xitus@gmail.com>       #
#                                                                       #
# This file is part of KIAUH - Klipper Installation And Update Helper   #
# https://github.com/th33xitus/kiauh                                    #
#                                                                       #
# This file may be distributed under the terms of the GNU GPLv3 license #
#=======================================================================#

set -e

#=================================================#
#============= INSTALL MJPG-STREAMER =============#
#=================================================#
########################################################
function mjpg-streamer_setup_dialog() {
  status_msg "Initializing mjpg-streamer installation ..."

  ### return early if python version check fails
  if [[ $(python3_check) == "false" ]]; then
    local error="Versioncheck failed! Python 3.7 or newer required!\n"
    error="${error} Please upgrade Python."
    print_error "${error}" && return
  fi

  ### return early if moonraker already exists 
  #local mjpg-streamer_services
  #mjpg-streamer_services=$(moonraker_systemd)#!!??
  #if [[ -n ${moonraker_services} ]]; then
  #  local error="At least one Moonraker service is already installed:"
  #  for s in ${moonraker_services}; do
  #    log_info "Found Moonraker service: ${s}"
  #    error="${error}\n ➔ ${s}"
  #  done
  #  print_error "${error}" && return
  #fi

  ### return early if klipper is not installed
  local klipper_services
  klipper_services=$(find_klipper_systemd) # function in utilies.sh
  if [[ -z ${klipper_services} ]]; then
    local error="Klipper not installed! Please install Klipper first!"
    log_error "Moonraker setup started without Klipper being installed. Aborting setup."
    print_error "${error}" && return
  fi

  local klipper_count user_input=() klipper_names=()
  klipper_count=$(echo "${klipper_services}" | wc -w )
  for service in ${klipper_services}; do
    klipper_names+=( "$(get_instance_name "${service}")" )
  done

  local mjpg_streamer_count
  if (( klipper_count == 1 )); then
    ok_msg "Klipper installation found!\n"
    mjpg_streamer_count=1
  elif (( klipper_count > 1 )); then
    top_border
    printf "|${green}%-55s${white}|\n" " ${klipper_count} Klipper instances found!"
    for name in "${klipper_names[@]}"; do
      printf "|${cyan}%-57s${white}|\n" " ● klipper-${name}"
    done
    blank_line
    echo -e "| The setup will apply the same names to mjpg-streamer! |"
    blank_line
    echo -e "| Please select the number of mjpg-streamer instances to|"
    echo -e "| install. Usually one mjpg-streamer instance per Klipper   |"
    echo -e "| instance is required, but you may not install more        |"
    echo -e "| mjpg-streamer instances than available Klipper instances. |"
    bottom_border

    ### ask for amount of instances
    local re="^[1-9][0-9]*$"
    while [[ ! ${mjpg_streamer_count} =~ ${re} || ${mjpg_streamer_count} -gt ${klipper_count} ]]; do
      read -p "${cyan}###### Number of mjpg-streamer instances to set up:${white} " -i "${klipper_count}" -e mjpg_streamer_count
      ### break if input is valid
      [[ ${mjpg_streamer_count} =~ ${re} && ${mjpg_streamer_count} -le ${klipper_count} ]] && break
      ### conditional error messages
      [[ ! ${mjpg_streamer_count} =~ ${re} ]] && error_msg "Input not a number"
      (( mjpg_streamer_count > klipper_count )) && error_msg "Number of mjpg-streamer instances larger than installed Klipper instances"
    done && select_msg "${mjpg_streamer_count}"
  else
    log_error "Internal error. klipper_count of '${klipper_count}' not equal or grather than one!"
    return 1
  fi

  user_input+=("${mjpg_streamer_count}")

  ### confirm instance amount
  local yn
  while true; do
    (( mjpg_streamer_count == 1 )) && local question="Install mjpg-streamer?"
    (( mjpg_streamer_count > 1 )) && local question="Install ${mjpg_streamer_count} mjpg-streamer instances?"
    read -p "${cyan}###### ${question} (Y/n):${white} " yn
    case "${yn}" in
      Y|y|Yes|yes|"")
        select_msg "Yes"
        break;;
      N|n|No|no)
        select_msg "No"
        abort_msg "Exiting mjpg-streamer setup ...\n"
        return;;
      *)
        error_msg "Invalid Input!";;
    esac
  done

  ### write existing klipper names into user_input array to use them as names for moonraker
  if (( klipper_count > 1 )); then
    for name in "${klipper_names[@]}"; do
      user_input+=("${name}")
    done
    echo -e ("${name}")
  fi

  (( mjpg_streamer_count > 1 )) && status_msg "Installing ${mjpg_streamer_count} mjpg-streamer instances ..."
  (( mjpg_streamer_count == 1 )) && status_msg "Installing mjpg-streamer ..."
  #moonraker_setup "${user_input[@]}"
  echo -e "${user_input[@]}"
}
##################################################################################################

function install_mjpg-streamer() {
  local webcamd="${KIAUH_SRCDIR}/resources/mjpg-streamer/webcamd"
  local webcam_txt="${KIAUH_SRCDIR}/resources/mjpg-streamer/webcam.txt"
  local service="${KIAUH_SRCDIR}/resources/mjpg-streamer/webcamd.service"
  local repo="https://github.com/jacksonliam/mjpg-streamer.git"

  ### return early if webcamd.service already exists
  if [[ -f "${SYSTEMD}/webcamd.service" ]]; then
    print_error "Looks like MJPG-streamer is already installed!\n Please remove it first before you try to re-install it!"
    return
  fi

  status_msg "Initializing MJPG-Streamer installation ..."

  ### check and install dependencies if missing
  local dep=(git cmake build-essential imagemagick libv4l-dev ffmpeg)
  if apt-cache search libjpeg62-turbo-dev | grep -Eq "^libjpeg62-turbo-dev "; then
    dep+=(libjpeg62-turbo-dev)
  elif apt-cache search libjpeg8-dev | grep -Eq "^libjpeg8-dev "; then
    dep+=(libjpeg8-dev)
  fi

  dependency_check "${dep[@]}"

  ### step 1: clone mjpg-streamer
  status_msg "Cloning MJPG-Streamer from ${repo} ..."
  [[ -d "${HOME}/mjpg-streamer" ]] && rm -rf "${HOME}/mjpg-streamer"

  cd "${HOME}" || exit 1
  if ! git clone "${repo}" "${HOME}/mjpg-streamer"; then
    print_error "Cloning MJPG-Streamer from\n ${repo}\n failed!"
    exit 1
  fi
  ok_msg "Cloning complete!"

  ### step 2: compiling mjpg-streamer
  status_msg "Compiling MJPG-Streamer ..."
  cd "${HOME}/mjpg-streamer/mjpg-streamer-experimental"
  if ! make; then
    print_error "Compiling MJPG-Streamer failed!"
    exit 1
  fi
  ok_msg "Compiling complete!"

  #step 3: install mjpg-streamer
  status_msg "Installing MJPG-Streamer ..."
  cd "${HOME}/mjpg-streamer" && mv mjpg-streamer-experimental/* .
  mkdir www-mjpgstreamer

  cat <<EOT >> ./www-mjpgstreamer/index.html
<html>
<head><title>mjpg_streamer test page</title></head>
<body>
<h1>Snapshot</h1>
<p>Refresh the page to refresh the snapshot</p>
<img src="./?action=snapshot" alt="Snapshot">
<h1>Stream</h1>
<img src="./?action=stream" alt="Stream">
</body>
</html>
EOT

  sudo cp "${webcamd}" "/usr/local/bin/webcamd"
  sudo sed -i "/^config_dir=/ s|=.*|=${KLIPPER_CONFIG}|" /usr/local/bin/webcamd # KLIPPER_CONFIG don´t work
  sudo sed -i "/MJPGSTREAMER_HOME/ s/pi/${USER}/" /usr/local/bin/webcamd
  sudo chmod +x /usr/local/bin/webcamd

  ### step 4: create webcam.txt config file
  [[ ! -d ${KLIPPER_CONFIG} ]] && mkdir -p "${KLIPPER_CONFIG}"
  if [[ ! -f "${KLIPPER_CONFIG}/webcam.txt" ]]; then
    status_msg "Creating webcam.txt config file ..."
    cp "${webcam_txt}" "${KLIPPER_CONFIG}/webcam.txt"
    ok_msg "Done!"
  fi

  ### step 5: create systemd service
  status_msg "Creating MJPG-Streamer service ..."
  sudo cp "${service}" "${SYSTEMD}/webcamd.service"
  sudo sed -i "s|%USER%|${USER}|" "${SYSTEMD}/webcamd.service"
  ok_msg "MJPG-Streamer service created!"

  ### step 6: enabling and starting mjpg-streamer service
  status_msg "Starting MJPG-Streamer service, please wait ..."
  sudo systemctl enable webcamd.service
  if sudo systemctl start webcamd.service; then
    ok_msg "MJPG-Streamer service started!"
  else
    status_msg "MJPG-Streamer service couldn't be started! No webcam connected?\n###### You need to manually restart the service once your webcam is set up correctly."
  fi

  ### step 6.1: create webcamd.log symlink
  [[ ! -d ${KLIPPER_LOGS} ]] && mkdir -p "${KLIPPER_LOGS}" #KLIPPER_LOGS don´t work
  if [[ -f "/var/log/webcamd.log" && ! -L "${KLIPPER_LOGS}/webcamd.log" ]]; then
    ln -s "/var/log/webcamd.log" "${KLIPPER_LOGS}/webcamd.log"
  fi

  ### step 6.2: add webcamd.log logrotate
  if [[ ! -f "/etc/logrotate.d/webcamd"  ]]; then
    status_msg "Create logrotate rule ..."
    sudo /bin/sh -c "cat > /etc/logrotate.d/webcamd" << EOF
/var/log/webcamd.log
{
    rotate 2
    weekly
    maxsize 32M
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
}
EOF
     ok_msg "Done!"
  fi

  ### step 7: check if user is in group "video"
  local usergroup_changed="false"
  if ! groups "${USER}" | grep -q "video"; then
    status_msg "Adding user '${USER}' to group 'video' ..."
    sudo usermod -a -G video "${USER}" && ok_msg "Done!"
    usergroup_changed="true"
  fi

  ### confirm message
  local confirm_msg="MJPG-Streamer has been set up!"
  if [[ ${usergroup_changed} == "true" ]]; then
    confirm_msg="${confirm_msg}\n ${yellow}INFO: Your User was added to a new group!${green}"
    confirm_msg="${confirm_msg}\n ${yellow}You need to relog/restart for the group to be applied!${green}"
  fi

  print_confirm "${confirm_msg}"

  ### print webcam ip adress/url
  local ip
  ip=$(hostname -I | cut -d" " -f1)
  local cam_url="http://${ip}:8080/?action=stream"
  local cam_url_alt="http://${ip}/webcam/?action=stream"
  echo -e " ${cyan}● Webcam URL:${white} ${cam_url}"
  echo -e " ${cyan}● Webcam URL:${white} ${cam_url_alt}"
  echo
}

#=================================================#
#============== REMOVE MJPG-STREAMER =============#
#=================================================#

function remove_mjpg-streamer() {
  ### remove MJPG-Streamer service
  if [[ -e "${SYSTEMD}/webcamd.service" ]]; then
    status_msg "Removing MJPG-Streamer service ..."
    sudo systemctl stop webcamd && sudo systemctl disable webcamd
    sudo rm -f "${SYSTEMD}/webcamd.service"
    ###reloading units
    sudo systemctl daemon-reload
    sudo systemctl reset-failed
    ok_msg "MJPG-Streamer Service removed!"
  fi

  ### remove webcamd from /usr/local/bin
  if [[ -e "/usr/local/bin/webcamd" ]]; then
    sudo rm -f "/usr/local/bin/webcamd"
  fi

  ### remove MJPG-Streamer directory
  if [[ -d "${HOME}/mjpg-streamer" ]]; then
    status_msg "Removing MJPG-Streamer directory ..."
    rm -rf "${HOME}/mjpg-streamer"
    ok_msg "MJPG-Streamer directory removed!"
  fi

  ### remove webcamd log and symlink
  [[ -f "/var/log/webcamd.log" ]] && sudo rm -f "/var/log/webcamd.log"
  [[ -L "${KLIPPER_LOGS}/webcamd.log" ]] && rm -f "${KLIPPER_LOGS}/webcamd.log"

  print_confirm "MJPG-Streamer successfully removed!"
}