# syntax=docker/dockerfile:1
FROM condaforge/miniforge3:24.9.2-0

LABEL org.opencontainers.image.title="dokkaebi-eggnog"
LABEL org.opencontainers.image.description="eggnog_env environment for the Dokkaebi metagenome pipeline"
LABEL org.opencontainers.image.source="https://github.com/ystone1101/metagenome-pipeline"

# Build context is the repository root (see docker/README.md), so this path
# resolves to environments/eggnog_env.yml in the repo.
COPY environments/eggnog_env.yml /tmp/environment.yml

RUN conda env create -f /tmp/environment.yml \
    && conda clean -afy \
    && rm -f /tmp/environment.yml

ENV PATH=/opt/conda/envs/eggnog_env/bin:$PATH

ENTRYPOINT ["conda", "run", "--no-capture-output", "-n", "eggnog_env"]
CMD ["emapper.py", "--version"]
