FROM ubuntu:latest

RUN useradd -m scheduler


COPY templates/* /home/scheduler/templates/
COPY public/images/* /home/scheduler/public/images/
COPY public/*.js /home/scheduler/public/
COPY public/*.html /home/scheduler/public/
COPY public/*.css /home/scheduler/public/
COPY public/*.pdf /home/scheduler/public/
COPY public/*.png /home/scheduler/public/
COPY public/*.ico /home/scheduler/public/
COPY email/* /home/scheduler/email/
COPY sms/* /home/scheduler/sms/
COPY docs/* /home/scheduler/docs/
COPY vendor/* /home/scheduler/vendor/


COPY Scheduler /home/scheduler
COPY *.pm /home/scheduler
COPY cpan* /home/scheduler

RUN apt-get -y update && \
	apt-get -y install libssl-dev && \
	apt-get -y install cron && \
	apt-get -y install gcc && \
    apt-get -y install perl --reinstall && \
	apt-get -y install cpanminus && \
	apt-get -y install carton


WORKDIR /home/scheduler

RUN carton install

USER scheduler

ENTRYPOINT carton exec -- morbo Scheduler
