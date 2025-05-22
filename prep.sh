#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# create-user.sh — Interactive helper to create a non-root sudo user,
#                  harden SSH, and migrate root SSH keys.
#
# Works on modern Ubuntu (20.04/22.04) but should be portable to most
# systemd-based Linux distributions that ship OpenSSH and use /etc/ssh/sshd_config.
# -----------------------------------------------------------------------------

# This line tells your computer to use a special program called 'bash' to run this script.
# Think of it like telling your computer which language to speak!

# ----------------------------------------------------------------------
#  Safety rails
# ----------------------------------------------------------------------
# These are like safety rules for our script. If something goes wrong,
# the script will stop right away so we can fix it, instead of making a bigger mess.
set -euo pipefail
# -e  : If any command fails, the script stops immediately. No more running!
# -u  : If we try to use a variable that hasn't been given a value, the script stops.
# -o pipefail : If we connect commands with a '|' (pipe) and one of them fails, the whole thing stops.

# --- OS Detection and Package Management Setup ---
# This part helps the script figure out what kind of Linux computer it's running on.
# Different Linux computers use different ways to install and update software.
if [ -f /etc/os-release ]; then
    # We read a special file that tells us about the operating system.
    . /etc/os-release
    OS_ID=$ID # This is like the computer's "family name" (e.g., "ubuntu", "amazon").
    OS_VERSION_ID=$VERSION_ID # This is like the computer's "version number" (e.g., "20.04", "2023").
else
    # If we can't find the special file, we can't figure out the OS, so we stop.
    echo "Error: Cannot detect OS. /etc/os-release not found." >&2
    exit 1
fi

# Now, based on the computer's "family name", we set up the right commands for updating and installing.
case "$OS_ID" in
    "ubuntu")
        echo "Detected Ubuntu ($OS_VERSION_ID). Using apt-get."
        PACKAGE_MANAGER="apt-get"
        UPDATE_COMMAND="sudo $PACKAGE_MANAGER update -qq" # Command to update the list of available software.
        INSTALL_COMMAND="sudo $PACKAGE_MANAGER install -yq" # Command to install new software.
        ;;
    "amazon"|"amzn") # This covers both "amazon" and "amzn" for Amazon Linux.
        echo "Detected Amazon Linux ($OS_VERSION_ID). Using dnf."
        PACKAGE_MANAGER="dnf"
        UPDATE_COMMAND="sudo $PACKAGE_MANAGER check-update -q" # Command to update the list of available software.
        INSTALL_COMMAND="sudo $PACKAGE_MANAGER install -yq" # Command to install new software.
        ;;
    *) # If it's not Ubuntu or Amazon Linux, we don't know how to proceed, so we stop.
        echo "Error: Unsupported Linux distribution: $OS_ID $OS_VERSION_ID" >&2
        exit 1
        ;;
esac

# First, let's update the list of available software.
# This is like refreshing the app store to see all the latest apps!
$UPDATE_COMMAND

# Now, let's install a cool new command-line program called 'zsh'.
# A command-line program (or 'shell') is how you talk to your computer using text commands.
# '-yq' means "yes" to any questions and "quiet" so it doesn't show too much text.
DEBIAN_FRONTEND=noninteractive $INSTALL_COMMAND zsh

# We're checking if 'zsh' was installed and where it lives on your computer.
ZSH_BIN="$(command -v zsh || true)"

# Add zsh to /etc/shells if missing
# This part makes sure your computer knows that 'zsh' is a valid shell program.
# It's like adding a new language to your computer's list of languages it can speak.
if [[ -n "$ZSH_BIN" && ! $(grep -Fx "$ZSH_BIN" /etc/shells) ]]; then
  echo "$ZSH_BIN" >> /etc/shells
fi


# ----------------------------------------------------------------------
#  1. Ask for a valid *new* username
# ----------------------------------------------------------------------
# We need to create a new user account for you to use.
# This loop keeps asking until you give a good username.
while true; do
    # 'read -rp' asks you a question and waits for you to type an answer.
    # 'username' is where your answer will be stored.
    read -rp "Enter a username you want to login as: " username
    # Username rules: must start with a lowercase letter, followed by
    # lowercase letters, digits, hyphens or underscores.
    # This is like checking if your username follows the rules, like no spaces or weird symbols.
    if [[ "$username" =~ ^[a-z][-a-z0-9_]*$ ]]; then
        break # If the username is good, we can stop asking.
    else
        # If the username is not good, we tell you why and ask again.
        echo "⚠️  Invalid username. Use lowercase letters, digits, underscores; must start with a letter."
    fi
done

# ----------------------------------------------------------------------
#  2. Read and confirm the password for the new user
# ----------------------------------------------------------------------
# Now we need a secret password for your new user account!
# This loop keeps asking until you type the same password twice.
while true; do
    # '-s' means "silent" so your password doesn't show up on the screen while you type it.
    read -rsp "Enter a password for that user: " password1; echo # Ask for the first password.
    read -rsp "Confirm password: "               password2; echo # Ask for the password again to make sure you typed it correctly.
    # We check if both passwords match and if you actually typed something.
    if [[ "$password1" == "$password2" && -n "$password1" ]]; then
        break # If they match, we can stop asking.
    else
        # If they don't match, we tell you and ask again.
        echo "⚠️  Passwords do not match. Please try again."
    fi
done

# ----------------------------------------------------------------------
#  3. Abort early if the user already exists
# ----------------------------------------------------------------------
# Before creating the user, we check if an account with that username already exists.
# We don't want to accidentally mess up an existing account!
if id "$username" &>/dev/null; then
    echo "❌ User $username already exists." >&2 # If it exists, we show an error.
    exit 1 # And the script stops.
fi

# ----------------------------------------------------------------------
#  4. Create the user with a bash login shell and add to sudoers
# ----------------------------------------------------------------------
# This is where we actually create your new user account!
default_shell="/bin/bash" # We'll start with 'bash' as the default command-line program.
# If 'zsh' was installed, we'll use that as your default command-line program instead.
[[ -x "$ZSH_BIN" ]] && default_shell="$ZSH_BIN"

# 'useradd' creates the new user.
# '--create-home' makes a special folder for your user (like your bedroom).
# '--shell' sets your default command-line program.
useradd --create-home --shell "$default_shell" "$username"

# This line sets the password for your new user. It's a bit like whispering the secret password to the computer.
echo "${username}:${password1}" | chpasswd
# 'usermod -aG sudo' gives your new user "super powers" (sudo).
# This means you can run important commands that usually only the computer's "boss" (root) can run.
usermod -aG sudo "$username"
# 'usermod -aG docker' gives your new user access to 'docker'.
# Docker is a tool for running special "containers" which are like tiny virtual computers.
usermod -aG docker "$username"

# ----------------------------------------------------------------------
#  5. Prepare the user’s ~/.ssh directory and copy root’s keys
# ----------------------------------------------------------------------
# SSH is a super secure way to log into your computer from another computer.
# It uses special "keys" instead of just passwords, like a secret handshake.

# 'mkdir -p' creates a hidden folder called '.ssh' inside your user's home folder.
# This is where your secret SSH keys will live.
mkdir -p /home/"$username"/.ssh
# 'chmod 700' sets special permissions for this folder.
# '700' means only YOU can read, write, and open this folder. No one else!
chmod 700 /home/"$username"/.ssh

# Copy root’s authorized_keys so the new user can SSH using the same key(s)
# The computer's "boss" (root) might have some secret keys already.
# We're copying those keys so your new user can also use them to log in.
cp /root/.ssh/authorized_keys /home/"$username"/.ssh/authorized_keys

# 'chmod 600' sets permissions for the secret key file.
# '600' means only YOU can read and write to this file. It's super secret!
chmod 600 /home/"$username"/.ssh/authorized_keys
# 'chown -R' changes who "owns" the folder and everything inside it.
# We're making sure your new user owns their secret SSH folder and keys.
chown -R "$username":"$username" /home/"$username"/.ssh

# ----------------------------------------------------------------------
#  6. Prep ZSH
# ----------------------------------------------------------------------
# If 'zsh' was installed, let's set it up nicely for your new user!
if [[ -x "$ZSH_BIN" ]]; then
  # This part writes some basic settings into a file called '.zshrc' in your home folder.
  # This file tells 'zsh' how to behave when you use it.
  cat > /home/"$username"/.zshrc <<'EOF'
# ~/.zshrc – minimal starter file
# This tells 'zsh' where to save your command history (all the commands you type).
export HISTFILE=~/.zsh_history
# This sets how many commands 'zsh' remembers in its history.
export HISTSIZE=10000
export SAVEHIST=10000
# These lines make sure your command history is saved properly and shared across different 'zsh' windows.
setopt inc_append_history share_history
# This sets what your command prompt looks like. It makes it colorful and shows your username and where you are.
PROMPT='%F{green}%n@%m%f:%F{blue}%~%f$ '
EOF
  # We make sure your new user owns their '.zshrc' settings file.
  chown "$username":"$username" /home/"$username"/.zshrc
fi


# ----------------------------------------------------------------------
#  7. Harden SSH daemon configuration
# ----------------------------------------------------------------------
# Now we're going to make the SSH login system even more secure!
# This is like putting extra locks on the door.
SSHCFG='/etc/ssh/sshd_config'                 # This is the main settings file for SSH.
CLOUDINIT='/etc/ssh/sshd_config.d/50-cloud-init.conf' # Sometimes there's another settings file from "cloud-init".

# This is a special helper function (like a mini-program) to change settings in the SSH file.
patch_line() {
  # Replace or append a key/value pair in sshd_config.
  # Usage: patch_line <Directive> <Value>
  local key=$1 # The setting we want to change (e.g., "PasswordAuthentication").
  local value=$2 # The new value for that setting (e.g., "no").

  # If the setting already exists in the file (even if it's commented out), we change it.
  # Otherwise, we add the setting to the end of the file.
  if grep -qiE "^\s*#?\s*${key}\s+" "$SSHCFG"; then
    # 'sed -Ei' is a powerful tool to find and replace text in files.
    # We're finding the old setting and replacing it with our new, more secure setting.
    sed -Ei "s|^\s*#?\s*${key}\s+.*|${key} ${value}|I" "$SSHCFG"
  else
    # If the setting isn't there, we just add it to the end of the file.
    echo "${key} ${value}" >> "$SSHCFG"
  fi
}

# Disable password auth & root login; disable PAM to avoid bypass
# We're telling SSH to NOT allow logging in with just a password.
# This makes it much safer because only your secret SSH keys will work.
patch_line "PasswordAuthentication" "no"
# We're also telling SSH to NOT allow the "boss" (root) user to log in directly.
# This is another security step to keep your computer safe.
patch_line "PermitRootLogin"        "no"
# 'UsePAM' is another setting related to how users log in. We're turning it off for extra security.
patch_line "UsePAM"                 "no"

# Remove cloud-init override file (if present) so it can’t re-enable passwords
# Sometimes, another program might try to change SSH settings back to less secure ones.
# We're removing its settings file to make sure our security changes stick!
if [[ -f $CLOUDINIT ]]; then
    rm -f "$CLOUDINIT" # 'rm -f' deletes the file.
fi

# ----------------------------------------------------------------------
#  7. Validate and reload sshd
# ----------------------------------------------------------------------
# Before we finish, we check if our SSH settings are correct.
# '-t' means "test" the settings without actually changing anything yet.
/usr/sbin/sshd -t          # syntax check; exits non-zero if invalid
# Now we restart the SSH service so all our new security settings take effect.
# 'systemctl restart ssh' is like turning the SSH program off and on again.
systemctl restart ssh      # graceful restart (Ubuntu service name)

# Hooray! The script is done!
echo "✅ User $username created and SSH hardened successfully."

# These next lines are copying some example settings files for other programs.
# Think of it like setting up some default game saves for new games.
cp n8n/example.env n8n/.env # Copying settings for 'n8n' (a workflow automation tool).
cp watchtower/example.env watchtower/.env # Copying settings for 'watchtower' (a tool to keep your Docker containers updated).
cp caddy/caddyfile/Caddyfile.example caddy/caddyfile/Caddyfile # Copying settings for 'caddy' (a web server).

# 'cd ~' changes your current location to your home folder.
cd ~
# We're moving the 'homelab' folder (where all these scripts and settings are)
# into your new user's home folder.
mv homelab /home/$username/homelab
# We make sure your new user "owns" the 'homelab' folder and everything inside it.
chown -R $username:$username /home/$username/homelab

# We're creating another hidden folder called '.config' in your home folder.
# This is a common place for programs to store their settings.
mkdir /home/$username/.config
# And again, we make sure your new user owns this new folder.
chown -R $username:$username /home/$username/.config
