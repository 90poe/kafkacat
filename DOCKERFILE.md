# Building a linux binary

To build a binary using the docker build do the following :

```
docker build --tag kafkacat . && \
docker run --entrypoint cat build /usr/bin/kafkacat > kafkacat && \
chmod 755 kafkacat
```

You will need the following dependencies to use the binary on ubuntu/debian :

```
sudo apt install libssl1.1 libsasl2-2 ca-certificates
```
