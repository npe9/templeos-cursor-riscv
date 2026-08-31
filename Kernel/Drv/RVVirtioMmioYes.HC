// VirtIO MMIO present (CONFIG_HAS_VIRTIO_MMIO).
Bool RVVirtioMmioEnabled()
{
  return TRUE;
}

I64 RVVirtioMmioBase()
{
  return CONFIG_VIRTIO_MMIO_BASE;
}

I64 RVVirtioMmioCount()
{
  return CONFIG_VIRTIO_MMIO_COUNT;
}

I64 RVVirtioMmioStride()
{
  return CONFIG_VIRTIO_MMIO_STRIDE;
}
