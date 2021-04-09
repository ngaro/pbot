FROM perl:5.32.1-buster

ARG REPO=https://github.com/pragma-/pbot.git
ARG BRANCH=master

WORKDIR /root
RUN git clone $REPO && cd /root/pbot && git checkout $BRANCH && \
echo "" | cpan && \
for module in $(cat MODULES) ; do \
  cpan -i $module && echo "$module tests: PASSED " >> /root/cpanresults || echo "$module tests: FAILED" >> /root/cpanresults ; \
done && \
perl -ne 'system "cpan -i -f $_" if(s/ tests: FAILED$//)' <  /root/cpanresults && \
rm -rf /root/pbot/.git /root/.cpan
WORKDIR /root/pbot
