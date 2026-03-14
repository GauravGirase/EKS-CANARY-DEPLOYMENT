FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY main.go .
RUN go mod init myapp && go build -o myapp .

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /app/myapp .
EXPOSE 8080
CMD ["./myapp"]
