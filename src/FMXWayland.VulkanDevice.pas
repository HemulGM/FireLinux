{ FMXWayland: Vulkan 1.0 offscreen device and resources. MIT license. }
unit FMXWayland.VulkanDevice;

interface

uses
  System.SysUtils, FMXWayland.VulkanApi;

type
  TVulkanDevice = class;

  TVulkanBuffer = class
  public
    Buffer: VkBuffer;
    Memory: VkDeviceMemory;
    Data: Pointer;
    Size: UInt64;
    constructor Create(ASize: UInt64; Usage: Cardinal);
    destructor Destroy; override;
  end;

  TVulkanImage = class(TInterfacedObject)
  public
    Image: VkImage;
    Memory: VkDeviceMemory;
    View: VkImageView;
    Sampler: VkSampler;
    Width, Height, Format, Samples, Aspect, Layout, Levels: Cardinal;
    constructor Create(AWidth, AHeight, AFormat, Usage, ASamples, AAspect: Cardinal; ALevels: Cardinal = 1);
    destructor Destroy; override;
    procedure Retain;
    procedure Release;
    procedure BarrierRange(Cmd: VkCommandBuffer; OldLayout, NewLayout, BaseLevel, LevelCount: Cardinal);
    procedure Barrier(Cmd: VkCommandBuffer; NewLayout: Cardinal);
    procedure Upload(Bits: Pointer; Pitch: Integer);
  end;

  TVulkanDevice = class
  private
    FMemory: VkPhysicalDeviceMemoryProperties;
    function MemoryType(Bits, Flags: Cardinal): Cardinal;
  public
    Instance: VkInstance;
    Physical: VkPhysicalDevice;
    Handle: VkDevice;
    Queue: VkQueue;
    QueueFamily: Cardinal;
    Pool: VkCommandPool;
    Properties: VkPhysicalDeviceProperties;
    DepthFormat: Cardinal;
    constructor Create;
    destructor Destroy; override;
    function BeginCommands: VkCommandBuffer;
    procedure Submit(Cmd: VkCommandBuffer);
    function SampleCount(Requested: Cardinal): Cardinal;
  end;

function VulkanDevice: TVulkanDevice;

procedure CheckVk(ResultCode: VkResult; const Operation: string);

implementation

uses
  System.Math, System.Generics.Collections;

var
  GDevice: TVulkanDevice;
  GDeviceLock: TObject;

procedure CheckVk(ResultCode: VkResult; const Operation: string);
begin
  if ResultCode <> VK_SUCCESS then
    raise Exception.CreateFmt('Vulkan: %s failed (%d)', [Operation, ResultCode]);
end;

function VulkanDevice: TVulkanDevice;
begin
  TMonitor.Enter(GDeviceLock);
  try
    if GDevice = nil then
      GDevice := TVulkanDevice.Create;
    Result := GDevice;
  finally
    TMonitor.Exit(GDeviceLock);
  end;
end;

constructor TVulkanDevice.Create;
var
  App: VkApplicationInfo;
  Info: VkInstanceCreateInfo;
  DeviceInfo: VkDeviceCreateInfo;
  QueueInfo: VkDeviceQueueCreateInfo;
  PoolInfo: VkCommandPoolCreateInfo;
  Devices: TArray<VkPhysicalDevice>;
  Families: TArray<VkQueueFamilyProperties>;
  Count, FamilyCount, I, J: Cardinal;
  Candidate: VkPhysicalDevice;
  Priority: Single;
  Fmt: VkFormatProperties;
  Layer: PAnsiChar;
  Layers: array[0..0] of PAnsiChar;
begin
  inherited;
  LoadVulkan;
  App := Default(VkApplicationInfo);
  App.sType := VK_STRUCTURE_TYPE_APPLICATION_INFO;
  App.pApplicationName := PAnsiChar('FMXWayland');
  App.apiVersion := $00400000; // Vulkan 1.0, no WSI or optional device extensions.
  Info := Default(VkInstanceCreateInfo);
  Info.sType := VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
  Info.pApplicationInfo := @App;
  if GetEnvironmentVariable('FMXWAYLAND_VULKAN_VALIDATION') = '1' then
  begin
    Layer := 'VK_LAYER_KHRONOS_validation';
    Layers[0] := Layer;
    Info.enabledLayerCount := 1;
    Info.ppEnabledLayerNames := @Layers[0];
  end;
  CheckVk(vkCreateInstance(@Info, nil, @Instance), 'create instance');
  Count := 0;
  CheckVk(vkEnumeratePhysicalDevices(Instance, @Count, nil), 'enumerate devices');
  if Count = 0 then
    raise Exception.Create('Vulkan: no physical device');
  SetLength(Devices, Count);
  CheckVk(vkEnumeratePhysicalDevices(Instance, @Count, @Devices[0]), 'enumerate devices');
  // Prefer a hardware adapter, retain CPU Vulkan implementations for headless testing.
  for I := 0 to Count - 1 do
  begin
    vkGetPhysicalDeviceProperties(Devices[I], @Properties);
    FamilyCount := 0;
    vkGetPhysicalDeviceQueueFamilyProperties(Devices[I], @FamilyCount, nil);
    SetLength(Families, FamilyCount);
    if FamilyCount = 0 then
      Continue;
    vkGetPhysicalDeviceQueueFamilyProperties(Devices[I], @FamilyCount, @Families[0]);
    Candidate := 0;
    for J := 0 to FamilyCount - 1 do
      if (Families[J].queueCount > 0) and ((Families[J].queueFlags and VK_QUEUE_GRAPHICS_BIT) <> 0) then
      begin
        Candidate := Devices[I];
        QueueFamily := J;
        Break;
      end;
    if Candidate <> 0 then
      Physical := Candidate;
    if (Candidate <> 0) and (Properties.deviceType <> VK_PHYSICAL_DEVICE_TYPE_CPU) then
      Break;
  end;
  if Physical = 0 then
    raise Exception.Create('Vulkan: no graphics queue');
  vkGetPhysicalDeviceProperties(Physical, @Properties);
  vkGetPhysicalDeviceMemoryProperties(Physical, @FMemory);
  vkGetPhysicalDeviceFormatProperties(Physical, VK_FORMAT_D24_UNORM_S8_UINT, @Fmt);
  DepthFormat := VK_FORMAT_D24_UNORM_S8_UINT;
  if (Fmt.optimalTilingFeatures and VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT) = 0 then
  begin
    DepthFormat := VK_FORMAT_D32_SFLOAT_S8_UINT;
    vkGetPhysicalDeviceFormatProperties(Physical, DepthFormat, @Fmt);
    if (Fmt.optimalTilingFeatures and VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT) = 0 then
      raise Exception.Create('Vulkan: no depth/stencil format');
  end;
  QueueInfo := Default(VkDeviceQueueCreateInfo);
  QueueInfo.sType := VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
  QueueInfo.queueFamilyIndex := QueueFamily;
  QueueInfo.queueCount := 1;
  Priority := 1;
  QueueInfo.pQueuePriorities := @Priority;
  DeviceInfo := Default(VkDeviceCreateInfo);
  DeviceInfo.sType := VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
  DeviceInfo.queueCreateInfoCount := 1;
  DeviceInfo.pQueueCreateInfos := @QueueInfo;
  CheckVk(vkCreateDevice(Physical, @DeviceInfo, nil, @Handle), 'create logical device');
  vkGetDeviceQueue(Handle, QueueFamily, 0, @Queue);
  PoolInfo := Default(VkCommandPoolCreateInfo);
  PoolInfo.sType := VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
  PoolInfo.flags := VK_COMMAND_POOL_CREATE_TRANSIENT_BIT;
  PoolInfo.queueFamilyIndex := QueueFamily;
  CheckVk(vkCreateCommandPool(Handle, @PoolInfo, nil, @Pool), 'create command pool');
end;

destructor TVulkanDevice.Destroy;
begin
  if Handle <> 0 then
  begin
    vkDeviceWaitIdle(Handle);
    if Pool <> 0 then
      vkDestroyCommandPool(Handle, Pool, nil);
    vkDestroyDevice(Handle, nil);
  end;
  if Instance <> 0 then
    vkDestroyInstance(Instance, nil);
  inherited;
end;

function TVulkanDevice.MemoryType(Bits, Flags: Cardinal): Cardinal;
var
  I: Cardinal;
begin
  for I := 0 to FMemory.memoryTypeCount - 1 do
    if ((Bits and (Cardinal(1) shl I)) <> 0) and
      ((FMemory.memoryTypes[I].propertyFlags and Flags) = Flags) then
      Exit(I);
  raise Exception.Create('Vulkan: no compatible memory type');
end;

function TVulkanDevice.BeginCommands: VkCommandBuffer;
var
  Allocate: VkCommandBufferAllocateInfo;
  BeginInfo: VkCommandBufferBeginInfo;
begin
  Allocate := Default(VkCommandBufferAllocateInfo);
  Allocate.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
  Allocate.commandPool := Pool;
  Allocate.level := VK_COMMAND_BUFFER_LEVEL_PRIMARY;
  Allocate.commandBufferCount := 1;
  CheckVk(vkAllocateCommandBuffers(Handle, @Allocate, @Result), 'allocate commands');
  BeginInfo := Default(VkCommandBufferBeginInfo);
  BeginInfo.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
  BeginInfo.flags := VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
  try
    CheckVk(vkBeginCommandBuffer(Result, @BeginInfo), 'begin commands');
  except
    vkFreeCommandBuffers(Handle, Pool, 1, @Result);
    raise;
  end;
end;

procedure TVulkanDevice.Submit(Cmd: VkCommandBuffer);
var
  Info: VkSubmitInfo;
  FenceInfo: VkFenceCreateInfo;
  Fence: VkFence;
begin
  Fence := 0;
  try
    CheckVk(vkEndCommandBuffer(Cmd), 'end commands');
    FenceInfo := Default(VkFenceCreateInfo);
    FenceInfo.sType := VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    Fence := 0;
    CheckVk(vkCreateFence(Handle, @FenceInfo, nil, @Fence), 'create fence');
    Info := Default(VkSubmitInfo);
    Info.sType := VK_STRUCTURE_TYPE_SUBMIT_INFO;
    Info.commandBufferCount := 1;
    Info.pCommandBuffers := @Cmd;
    CheckVk(vkQueueSubmit(Queue, 1, @Info, Fence), 'submit commands');
    CheckVk(vkWaitForFences(Handle, 1, @Fence, VK_TRUE, High(UInt64)), 'wait for commands');
  finally
    if Fence <> 0 then
      vkDestroyFence(Handle, Fence, nil);
    vkFreeCommandBuffers(Handle, Pool, 1, @Cmd);
  end;
end;

function TVulkanDevice.SampleCount(Requested: Cardinal): Cardinal;
var
  Flags: Cardinal;
  ColorProperties, DepthProperties: VkImageFormatProperties;
begin
  CheckVk(vkGetPhysicalDeviceImageFormatProperties(Physical, VK_FORMAT_B8G8R8A8_UNORM,
      VK_IMAGE_TYPE_2D, VK_IMAGE_TILING_OPTIMAL, VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT, 0,
      @ColorProperties), 'query color sample counts');
  CheckVk(vkGetPhysicalDeviceImageFormatProperties(Physical, DepthFormat,
      VK_IMAGE_TYPE_2D, VK_IMAGE_TILING_OPTIMAL, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT, 0,
      @DepthProperties), 'query depth sample counts');
  Flags := Properties.limits.framebufferColorSampleCounts and Properties.limits.framebufferDepthSampleCounts
    and Properties.limits.framebufferStencilSampleCounts and ColorProperties.sampleCounts and DepthProperties.sampleCounts;
  Result := Requested;
  while (Result > 1) and ((Flags and Result) = 0) do
    Result := Result shr 1;
end;

constructor TVulkanBuffer.Create(ASize: UInt64; Usage: Cardinal);
var
  Info: VkBufferCreateInfo;
  Requirements: VkMemoryRequirements;
  Allocate: VkMemoryAllocateInfo;
  Dev: TVulkanDevice;
begin
  inherited Create;
  Dev := VulkanDevice;
  Size := ASize;
  Info := Default(VkBufferCreateInfo);
  Info.sType := VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
  Info.size := Max(UInt64(4), Size);
  Info.usage := Usage;
  Info.sharingMode := VK_SHARING_MODE_EXCLUSIVE;
  CheckVk(vkCreateBuffer(Dev.Handle, @Info, nil, @Buffer), 'create buffer');
  vkGetBufferMemoryRequirements(Dev.Handle, Buffer, @Requirements);
  Allocate := Default(VkMemoryAllocateInfo);
  Allocate.sType := VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
  Allocate.allocationSize := Requirements.size;
  Allocate.memoryTypeIndex := Dev.MemoryType(Requirements.memoryTypeBits,
    VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT or VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
  CheckVk(vkAllocateMemory(Dev.Handle, @Allocate, nil, @Memory), 'allocate buffer memory');
  CheckVk(vkBindBufferMemory(Dev.Handle, Buffer, Memory, 0), 'bind buffer memory');
  CheckVk(vkMapMemory(Dev.Handle, Memory, 0, Requirements.size, 0, @Data), 'map buffer');
end;

destructor TVulkanBuffer.Destroy;
begin
  if GDevice <> nil then
  begin
    if Data <> nil then
      vkUnmapMemory(GDevice.Handle, Memory);
    if Buffer <> 0 then
      vkDestroyBuffer(GDevice.Handle, Buffer, nil);
    if Memory <> 0 then
      vkFreeMemory(GDevice.Handle, Memory, nil);
  end;
  inherited;
end;

constructor TVulkanImage.Create(AWidth, AHeight, AFormat, Usage, ASamples, AAspect, ALevels: Cardinal);
var
  Info: VkImageCreateInfo;
  Requirements: VkMemoryRequirements;
  Allocate: VkMemoryAllocateInfo;
  ViewInfo: VkImageViewCreateInfo;
  SamplerInfo: VkSamplerCreateInfo;
  Dev: TVulkanDevice;
begin
  inherited Create;
  Dev := VulkanDevice;
  Width := AWidth;
  Height := AHeight;
  Format := AFormat;
  Samples := ASamples;
  Aspect := AAspect;
  Levels := ALevels;
  Info := Default(VkImageCreateInfo);
  Info.sType := VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
  Info.imageType := VK_IMAGE_TYPE_2D;
  Info.format := Format;
  Info.extent.width := Width;
  Info.extent.height := Height;
  Info.extent.depth := 1;
  Info.mipLevels := Levels;
  Info.arrayLayers := 1;
  Info.samples := Samples;
  Info.tiling := VK_IMAGE_TILING_OPTIMAL;
  Info.usage := Usage;
  CheckVk(vkCreateImage(Dev.Handle, @Info, nil, @Image), 'create image');
  vkGetImageMemoryRequirements(Dev.Handle, Image, @Requirements);
  Allocate := Default(VkMemoryAllocateInfo);
  Allocate.sType := VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
  Allocate.allocationSize := Requirements.size;
  Allocate.memoryTypeIndex := Dev.MemoryType(Requirements.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
  CheckVk(vkAllocateMemory(Dev.Handle, @Allocate, nil, @Memory), 'allocate image memory');
  CheckVk(vkBindImageMemory(Dev.Handle, Image, Memory, 0), 'bind image memory');
  ViewInfo := Default(VkImageViewCreateInfo);
  ViewInfo.sType := VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
  ViewInfo.image := Image;
  ViewInfo.viewType := VK_IMAGE_VIEW_TYPE_2D;
  ViewInfo.format := Format;
  ViewInfo.subresourceRange.aspectMask := Aspect;
  ViewInfo.subresourceRange.levelCount := Levels;
  ViewInfo.subresourceRange.layerCount := 1;
  CheckVk(vkCreateImageView(Dev.Handle, @ViewInfo, nil, @View), 'create image view');
  if (Usage and VK_IMAGE_USAGE_SAMPLED_BIT) <> 0 then
  begin
    SamplerInfo := Default(VkSamplerCreateInfo);
    SamplerInfo.sType := VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
    SamplerInfo.magFilter := VK_FILTER_LINEAR;
    SamplerInfo.minFilter := VK_FILTER_LINEAR;
    SamplerInfo.mipmapMode := VK_SAMPLER_MIPMAP_MODE_NEAREST;
    SamplerInfo.addressModeU := VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    SamplerInfo.addressModeV := VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    SamplerInfo.addressModeW := VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    SamplerInfo.maxLod := Levels - 1;
    CheckVk(vkCreateSampler(Dev.Handle, @SamplerInfo, nil, @Sampler), 'create sampler');
  end;
end;

destructor TVulkanImage.Destroy;
begin
  if GDevice <> nil then
  begin
    if Sampler <> 0 then
      vkDestroySampler(GDevice.Handle, Sampler, nil);
    if View <> 0 then
      vkDestroyImageView(GDevice.Handle, View, nil);
    if Image <> 0 then
      vkDestroyImage(GDevice.Handle, Image, nil);
    if Memory <> 0 then
      vkFreeMemory(GDevice.Handle, Memory, nil);
  end;
  inherited;
end;

procedure TVulkanImage.Retain;
begin
  _AddRef;
end;

procedure TVulkanImage.Release;
begin
  _Release;
end;

procedure TVulkanImage.BarrierRange(Cmd: VkCommandBuffer; OldLayout, NewLayout, BaseLevel, LevelCount: Cardinal);
var
  B: VkImageMemoryBarrier;
begin
  B := Default(VkImageMemoryBarrier);
  B.sType := VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
  B.oldLayout := OldLayout;
  B.newLayout := NewLayout;
  B.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  B.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  B.image := Image;
  B.subresourceRange.aspectMask := Aspect;
  B.subresourceRange.baseMipLevel := BaseLevel;
  B.subresourceRange.levelCount := LevelCount;
  B.subresourceRange.layerCount := 1;
  if OldLayout <> VK_IMAGE_LAYOUT_UNDEFINED then
    B.srcAccessMask := VK_ACCESS_MEMORY_WRITE_BIT or VK_ACCESS_MEMORY_READ_BIT;
  B.dstAccessMask := VK_ACCESS_MEMORY_WRITE_BIT or VK_ACCESS_MEMORY_READ_BIT;
  vkCmdPipelineBarrier(Cmd, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
    0, 0, nil, 0, nil, 1, @B);
end;

procedure TVulkanImage.Barrier(Cmd: VkCommandBuffer; NewLayout: Cardinal);
begin
  BarrierRange(Cmd, Layout, NewLayout, 0, Levels);
  Layout := NewLayout;
end;

procedure TVulkanImage.Upload(Bits: Pointer; Pitch: Integer);
var
  Staging: TVulkanBuffer;
  Cmd: VkCommandBuffer;
  Region: VkBufferImageCopy;
  Y, Level, W, H, NextW, NextH: Cardinal;
  Blit: VkImageBlit;
begin
  TMonitor.Enter(VulkanDevice);
  try
    Staging := TVulkanBuffer.Create(UInt64(Width) * Height * 4, VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
    try
      for Y := 0 to Height - 1 do
        Move(PByte(NativeUInt(Bits) + NativeUInt(Y) * NativeUInt(Pitch))^,
          PByte(NativeUInt(Staging.Data) + NativeUInt(Y) * Width * 4)^, Width * 4);
      Cmd := VulkanDevice.BeginCommands;
      Barrier(Cmd, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
      Region := Default(VkBufferImageCopy);
      Region.imageSubresource.aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
      Region.imageSubresource.layerCount := 1;
      Region.imageExtent.width := Width;
      Region.imageExtent.height := Height;
      Region.imageExtent.depth := 1;
      vkCmdCopyBufferToImage(Cmd, Staging.Buffer, Image, Layout, 1, @Region);
      W := Width;
      H := Height;
      for Level := 1 to Levels - 1 do
      begin
        NextW := Max(Cardinal(1), W shr 1);
        NextH := Max(Cardinal(1), H shr 1);
        BarrierRange(Cmd, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, Level - 1, 1);
        Blit := Default(VkImageBlit);
        Blit.srcSubresource.aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
        Blit.srcSubresource.mipLevel := Level - 1;
        Blit.srcSubresource.layerCount := 1;
        Blit.srcOffsets[1].x := W;
        Blit.srcOffsets[1].Y := H;
        Blit.srcOffsets[1].z := 1;
        Blit.dstSubresource.aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
        Blit.dstSubresource.mipLevel := Level;
        Blit.dstSubresource.layerCount := 1;
        Blit.dstOffsets[1].x := NextW;
        Blit.dstOffsets[1].Y := NextH;
        Blit.dstOffsets[1].z := 1;
        vkCmdBlitImage(Cmd, Image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
          Image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, @Blit, VK_FILTER_LINEAR);
        BarrierRange(Cmd, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, Level - 1, 1);
        W := NextW;
        H := NextH;
      end;
      BarrierRange(Cmd, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, Levels - 1, 1);
      Layout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
      VulkanDevice.Submit(Cmd);
    finally
      Staging.Free;
    end;
  finally
    TMonitor.Exit(VulkanDevice);
  end;
end;

initialization
  GDeviceLock := TObject.Create;

finalization
  FreeAndNil(GDevice);
  GDeviceLock.Free;

end.

