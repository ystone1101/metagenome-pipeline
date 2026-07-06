# syntax=docker/dockerfile:1
FROM condaforge/miniforge3:24.9.2-0

LABEL org.opencontainers.image.title="dokkaebi-kneaddata"
LABEL org.opencontainers.image.description="KneadData_env environment for the Dokkaebi metagenome pipeline"
LABEL org.opencontainers.image.source="https://github.com/ystone1101/metagenome-pipeline"

# Build context is the repository root (see docker/README.md), so this path
# resolves to environments/kneaddata_env.yml in the repo.
COPY environments/kneaddata_env.yml /tmp/environment.yml

RUN conda env create -f /tmp/environment.yml \
    && conda clean -afy \
    && rm -f /tmp/environment.yml

ENV PATH=/opt/conda/envs/KneadData_env/bin:$PATH

ENTRYPOINT ["conda", "run", "--no-capture-output", "-n", "KneadData_env"]
CMD ["kneaddata", "--version"]
