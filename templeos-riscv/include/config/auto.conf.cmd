autoconfig := include/config/auto.conf

deps_config := \
	Kconfig \
	Kconfig.machines \

$(autoconfig): $(deps_config)
$(deps_config): ;
