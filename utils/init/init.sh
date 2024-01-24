#!/usr/bin/env bash

sudo yum install -y lrzsz curl git bzip2 npm docker-compose-plugin
~/game-server/utils/init/zsh_install.sh
~/game-server/utils/init/oh_my_zsh_install.sh

git clone git@github.com:wting/autojump.git
cd autojump
./install.py

git clone git@github.com:zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone git@github.com:zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone --depth=1 git@github.com:romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k


~/game-server/utils/init/nvm_install.sh
cp ~/game-server/utils/init/.zshrc ~
source ~/.zshrc
nvm install 14
chsh -s /usr/local/bin/zsh