# ACR token generator

This token generate created to accomodate use cases that not suppported by managed ACR credential helper.
Currently, two modes to generate temporary access and secret key are supported: OIDC and KV by setting `MODE` variable.

The build and push image is still manual.

## Build

```
docker buildx build --platform linux/amd64 . -t opanmustopah/acr-token-generator:<tag>
```

## Push

```
docker push opanmustopah/acr-token-generator:<tag>
```
