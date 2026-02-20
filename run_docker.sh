docker run --rm -it \
    -e HOST_UID=$(id -u) \
    -e HOST_GID=$(id -g) \
    -v /data/alvin/Databases:/home/user/Databases:ro \
    -v /data/alvin/hg38annotate/TestData:/data \
    -v /data/alvin/annovar/annovar-fast:/data/alvin/annovar/annovar-fast:ro \
    -v /data/alvin/annovar/humandb-tbi:/data/alvin/annovar/humandb-tbi:ro \
    hg38annotate:latest bash
