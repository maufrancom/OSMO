// SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// SPDX-License-Identifier: Apache-2.0

package utils

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/prometheus"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	semconv "go.opentelemetry.io/otel/semconv/v1.21.0"

	promclient "github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	sharedutils "go.corp.nvidia.com/osmo/utils"
)

// OTELConfig holds configuration for the OpenTelemetry metrics pipeline.
type OTELConfig struct {
	PrometheusPort int
	ServiceName    string
	ServiceVersion string
	Enabled        bool
}

// InitOTEL initialises the Prometheus metric pipeline, sets the global MeterProvider,
// starts the Prometheus scrape endpoint, and returns pre-created instrument handles
// plus a shutdown function.
//
// On success the caller must invoke the returned shutdown function (typically via
// defer) to flush pending metrics before process exit.
//
// On error the caller should fall back to NewNoopInstruments() so that call sites
// never need nil checks.
func InitOTEL(ctx context.Context, config OTELConfig) (*Instruments, func(context.Context) error, error) {
	registry := promclient.NewRegistry()
	exporter, err := prometheus.New(prometheus.WithRegisterer(registry))
	if err != nil {
		return nil, nil, fmt.Errorf("failed to create Prometheus exporter: %w", err)
	}

	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName(config.ServiceName),
			semconv.ServiceVersion(config.ServiceVersion),
		),
	)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to create resource: %w", err)
	}

	provider := sdkmetric.NewMeterProvider(
		sdkmetric.WithReader(exporter),
		sdkmetric.WithResource(res),
	)

	otel.SetMeterProvider(provider)

	meter := provider.Meter(config.ServiceName)
	inst, err := NewInstruments(meter)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to create instruments: %w", err)
	}

	// Start Prometheus scrape endpoint
	mux := http.NewServeMux()
	mux.Handle("/metrics", promhttp.HandlerFor(registry, promhttp.HandlerOpts{}))
	server := &http.Server{
		Addr:    fmt.Sprintf("0.0.0.0:%d", config.PrometheusPort),
		Handler: mux,
	}
	go func() {
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Printf("Prometheus metrics server error: %v", err)
		}
	}()

	shutdown := func(ctx context.Context) error {
		if shutdownErr := server.Shutdown(ctx); shutdownErr != nil {
			log.Printf("Error shutting down Prometheus server: %v", shutdownErr)
		}
		return provider.Shutdown(ctx)
	}

	return inst, shutdown, nil
}

// otelFlagPointers holds pointers to flag values for OTEL configuration.
type otelFlagPointers struct {
	enable         *bool
	prometheusPort *int
	component      *string
	version        *string
}

// RegisterOTELFlags registers OpenTelemetry metrics command-line flags and
// returns a function that builds an OTELConfig after flag.Parse() is called.
func RegisterOTELFlags(defaultComponent string) func() OTELConfig {
	ptrs := &otelFlagPointers{
		enable: flag.Bool("metricsOtelEnable",
			sharedutils.GetEnvBool("METRICS_OTEL_ENABLE", false),
			"Enable OpenTelemetry metrics"),
		prometheusPort: flag.Int("metricsPrometheusPort",
			sharedutils.GetEnvInt("METRICS_PROMETHEUS_PORT", 9464),
			"Port on which the Prometheus scrape endpoint is exposed"),
		component: flag.String("metricsOtelCollectorComponent",
			sharedutils.GetEnv("METRICS_OTEL_COLLECTOR_COMPONENT", defaultComponent),
			"Service name for OpenTelemetry metrics"),
		version: flag.String("serviceVersion",
			sharedutils.GetEnv("SERVICE_VERSION", "unknown"),
			"Service version for OpenTelemetry metrics"),
	}

	return func() OTELConfig {
		return OTELConfig{
			PrometheusPort: *ptrs.prometheusPort,
			ServiceName:    *ptrs.component,
			ServiceVersion: *ptrs.version,
			Enabled:        *ptrs.enable,
		}
	}
}
