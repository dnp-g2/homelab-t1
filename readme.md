This is a collection of docker-compose files for my home lab. There will be a video added for each service over time. I will be using Hostinger for all hosting. Visit [Hostinger](https://hostinger.com/mattw) for more information. If you sign up for anything there, use coupon code `mattw` for 10% off.

## Services

- n8n
- searxng
- perplexica
- firecrawl
- openwebui
- qdrant
- budibase
- postgres
- caddy
- watchtower

## Goals

I want to have a home lab that is self-hosted and runs on docker. I want to be able to access all of the services from the internet. But I don't want to let anyone access them...just me. n8n will be publicly accessible, but require authentication. The main thing that allows for this is Tailscale, which has a free plan that will let us do all we need.

## Video

This first section is covered in a video on my channel, sponsored by [Hostinger](https://hostinger.com/mattw). Embed will be added after its posted.


## Hostinger

If you want to follow along with everything I am doing, you can sign up for a Hostinger account at [Hostinger](https://hostinger.com/mattw) and use the coupon code `mattw` for 10% off. Select the KVM2 plan. You can choose any template you like, but I am going to start with just the Docker install. Once it is setup, SSH into the server as the user root and we need to do a few things.

1.  Create a new user account. You could use the default `ubuntu` user, but I prefer to create a new one for my name, matt. You use your name. `adduser matt`.
2.  Allow the user to sudo: `usermod -aG sudo matt`
3.  Add your user to the docker group: `sudo usermod -aG docker matt`
4.  Log out and copy your public key to the server: `ssh-copy-id -i keyname matt@<your-server-ip>`
5.  SSH in as the new user: `ssh matt@<your-server-ip>`
6.  Edit /etc/ssh/sshd_config

    a. Change `PasswordAuthentication` from `yes` to `no`

    b. Change `PermitRootLogin` from `yes` to `no`

    c. Change `UsePAM` from `yes` to `no`

7.  Delete /etc/ssh/sshd_config.d/50-cloud-init.conf
8.  Restart the ssh service: `sudo systemctl restart ssh`
9.  Log out and log back in as your new user.
10. Clone this repo to your home directory: `git clone https://github.com/technovangelist/homelab.git`

## Tailscale

The first step is to get a Tailscale account and add you home machine to your tailnet. You can do this by downloading the Tailscale app from the [Tailscale website](https://tailscale.com/).

After its installed, you need a key to add your docker containers to the tailnet. I found the easiest way to do it is to add the key to a docker secret.

1.  Create a folder called `~/.config` on the home directory for the user you are logged in as. 
2.  Create a file called `tsauthkey` in the `~/.config` folder.
3.  Go to the tailscale admin page, click on Settings. On the left go to Keys. Click the button `Generate auth key...`.
4.  Enable `Reusable`. Click `Generate key`.
5.  Add the key to the `tsauthkey` file.
6.  Make the file only readable by the user: `chmod 600 ~/.config/tsauthkey`

## n8n

1. Navigate into the n8n directory: `cd homelab/n8n`
2. Copy the example.env file to .env: `cp example.env .env`
3. Edit the .env file.

   a. `N8N_HOST` should be the hostname of your server.
   b.  `WEBHOOK_URL` should be the URL of your server. In my case they are the same.
   c. `GENERIC_TIMEZONE` should be your timezone.

4.  Start the n8n container: `docker compose up -d`

## Watchtower

This will update all the containers to the latest version every day at 4am

1. Navigate into the watchtower directory: `cd homelab/watchtower`
2. Change the Timezone to where ever you are. 
3. Start the watchtower container: `docker compose up -d`