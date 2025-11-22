package env

import (
	"log"
	"os"
	"strconv"
)

func getEnv(name string) string {
	valStr, exists := os.LookupEnv(name)
	if !exists {
		log.Fatal("Environment variable not set: ", name)
	}
	return valStr
}

func getEnvAsBool(name string) bool {
	valStr := getEnv(name)
	return valStr == "1"
}

func getEnvAsInt(name string) int {
	valStr := getEnv(name)
	intValue, err := strconv.Atoi(valStr)
	if err != nil {
		log.Fatal("Error parsing integer environment variable: ", name)
	}
	return intValue
}

func GetTailguardConfig() TailGuardConfig {
	return TailGuardConfig{
		ExposeHost:  getEnvAsBool("TG_EXPOSE_HOST"),
		ClientMode:  getEnvAsBool("TG_CLIENT_MODE"),
		Nameservers: getEnv("TG_NAMESERVERS"),

		WireGuardDevice:       getEnv("WG_DEVICE"),
		WireGuardIsolatePeers: getEnvAsBool("WG_ISOLATE_PEERS"),

		TailscaleDevice: getEnv("TS_DEVICE"),
		TailscalePort:   getEnvAsInt("TS_PORT"),
	}
}
