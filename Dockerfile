FROM perl:5.32.1-buster
WORKDIR /root
RUN git clone https://github.com/pragma-/pbot.git
RUN echo "" | cpan ; for module in $(cat /root/pbot/MODULES) ; do cpan -i $module && echo "$module tests: PASSED " >> /root/cpanresults || echo "$module tests: FAILED" >> /root/cpanresults ; done ; perl -ne 'system "cpan -i -f $_" if(s/ tests: FAILED$//)' <  /root/cpanresults ; rm -rf /root/pbot/.git /root/.cpan
WORKDIR /root/pbot
