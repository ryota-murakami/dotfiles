alias ll="ls -l"
alias d='cd ~/repository'
alias c='clear'
export PATH="$HOME/node_modules/.bin:$HOME/.composer/vendor/bin:$HOME/.rbenv/bin:$HOME/.rbenv/versions/2.2.0/bin:$PATH"
eval "$(rbenv init -)"
export DOCKER_CERT_PATH=/Users/tokyorefrain/.boot2docker/certs/boot2docker-vm
export DOCKER_TLS_VERIFY=1
export DOCKER_HOST=tcp://192.168.59.103:2376
eval "$(rbenv init -)"
source /usr/local/etc/bash_completion.d/git-prompt.sh
source /usr/local/etc/bash_completion.d/git-completion.bash
