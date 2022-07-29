FROM golang:1.18

RUN mkdir /webserver
WORKDIR /webserver

COPY go.mod go.sum server.crt server.key main.go .
RUN go build -v -o conversion-webhook-server .

ENTRYPOINT ["/webserver/conversion-webhook-server"]
