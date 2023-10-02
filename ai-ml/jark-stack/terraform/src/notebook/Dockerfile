FROM cschranz/gpu-jupyter:v1.5_cuda-11.6_ubuntu-20.04_python-only

USER root

RUN conda install -c anaconda libstdcxx-ng

RUN cp /opt/conda/lib/libstdc++.so.6.0.31 /usr/lib/x86_64-linux-gnu/ && \
  cd /usr/lib/x86_64-linux-gnu && \
  rm -f libstdc++.so.6 && \
  ln -s libstdc++.so.6.0.31 libstdc++.so.6
