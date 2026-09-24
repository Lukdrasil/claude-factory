FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS build
RUN apk add --no-cache clang build-base zlib-dev
WORKDIR /src
COPY . .
RUN rid=linux-musl-$(uname -m | sed 's/x86_64/x64/; s/aarch64/arm64/') \
 && dotnet publish FactoryUi.csproj -c Release -r "$rid" -o /app

FROM mcr.microsoft.com/dotnet/runtime-deps:10.0-alpine
RUN apk add --no-cache git
WORKDIR /app
COPY --from=build /app .
ENV ASPNETCORE_HTTP_PORTS=8080 HOME=/tmp
EXPOSE 8080
ENTRYPOINT ["./FactoryUi"]
