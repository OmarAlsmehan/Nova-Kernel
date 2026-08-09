obj-$(CONFIG_SEC_MISC)			+= sec_misc.o
obj-$(CONFIG_SEC_SMEM)			+= sec_smem.o
obj-$(CONFIG_ARGOS)  += sec_argos.o
ifneq ($(CONFIG_VBUS_NOTIFIER),)
ifeq ($(CONFIG_VBUS_NOTIFIER_MODULE),)
obj-y	+= vbus_notifier.o
else
obj-m	+= vbus_notifier.o
endif
endif
