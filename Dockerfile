FROM nimlang/nim:1.4.8
WORKDIR /app

COPY graphql.nimble .
RUN nimble install --depsOnly -y --verbose
COPY . .
RUN nim c -d:release playground/swserver

EXPOSE 8547

ENTRYPOINT ./playground/swserver starwars --bind:0.0.0.0:8547
