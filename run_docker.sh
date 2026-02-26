docker run --rm -it \
    -e HOST_UID=$(id -u) \
    -e HOST_GID=$(id -g) \
    -e HUMANDB=/data/alvin/annovar/humandb-tbi \
    --security-opt seccomp=unconfined \
    -v /data/alvin/Databases/hg38annotate:/home/user/Databases/hg38annotate:ro \
    -v /data/alvin/hg38annotate/TestData:/data \
    -v /data/alvin/annovar/annovar-fast:/data/alvin/annovar/annovar-fast:ro \
    -v /data/alvin/annovar/humandb-tbi:/data/alvin/annovar/humandb-tbi:ro \
    hg38annotate:latest bash
