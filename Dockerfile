FROM ubuntu:20.04

ENV container docker
ENV DEBIAN_FRONTEND noninteractive

# Install locale
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales && \
    echo "$LANG UTF-8" >> /etc/locale.gen && \
    locale-gen && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Timezone
ENV TZ=Asia/Seoul
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install systemd
RUN apt-get update && apt-get install -y \
    dbus dbus-x11 systemd && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* &&\
    dpkg-divert --local --rename --add /sbin/udevadm &&\
    ln -s /bin/true /sbin/udevadm
RUN systemctl disable systemd-resolved
VOLUME ["/sys/fs/cgroup"]
STOPSIGNAL SIGRTMIN+3
CMD [ "/sbin/init" ]

# Install GNOME
# NOTE if you want plain gnome, use: apt-get install -y --no-install-recommends gnome-session gnome-terminal and remove the modification of /etc/gdm3/custom.conf
#   && apt-get install -y --no-install-recommends gnome-session gnome-terminal \
RUN apt-get update \
  && apt-get install -y ubuntu-desktop fcitx-config-gtk gnome-tweak-tool gnome-usage \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && sed -i 's/\[daemon\]/[daemon]\nInitialSetupEnable=false/' /etc/gdm3/custom.conf


# Install TigerVNC server
# TODO set VNC port in service file > exec command
# TODO check if it works with default config file
# NOTE tigervnc because of XKB extension: https://github.com/i3/i3/issues/1983
RUN apt-get update \
  && apt-get install -y tigervnc-common tigervnc-scraping-server tigervnc-standalone-server tigervnc-xorg-extension \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# NOTE logout will stop tigervnc service -> need to manually start (gdm for graphical login is not working)
COPY tigervnc@.service /etc/systemd/system/tigervnc@.service
RUN systemctl enable tigervnc@:1
EXPOSE 5901

# Install noVNC
# TODO novnc depends on net-tools until version 1.1.0: https://github.com/novnc/noVNC/issues/1075
RUN apt-get update && apt-get install -y \
    net-tools novnc \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*
RUN ln -s /usr/share/novnc/vnc_lite.html /usr/share/novnc/index.html
# TODO specify options like ports as environment variables -> source variables in service via EnvironmentFile=/path/to/env
COPY novnc.service /etc/systemd/system/novnc.service
RUN systemctl enable novnc
EXPOSE 6080

# Create unprivileged user
# NOTE user hardcoded in tigervnc.service
# NOTE alternative is to use libnss_switch and create user at runtime -> use entrypoint script
ARG UID=1000
ARG USER=default
RUN useradd ${USER} -u ${UID} -U -d /home/${USER} -m -s /bin/bash
RUN apt-get update && apt-get install -y sudo && apt-get clean && rm -rf /var/lib/apt/lists/* && \
    echo "${USER} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/${USER}" && \
    chmod 440 "/etc/sudoers.d/${USER}"
USER "${USER}"
ENV USER="${USER}" \
    HOME="/home/${USER}"
WORKDIR "/home/${USER}"

# Set up VNC
RUN mkdir -p $HOME/.vnc
COPY xstartup $HOME/.vnc/xstartup
RUN echo "welcome" | vncpasswd -f >> $HOME/.vnc/passwd && chmod 600 $HOME/.vnc/passwd

# switch back to root to start systemd
USER root
