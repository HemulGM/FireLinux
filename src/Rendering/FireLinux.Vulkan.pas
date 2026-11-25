{ FireLinux: native Vulkan TContext3D for offscreen FMX viewports. MIT license. }
unit FireLinux.Vulkan;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Math.Vectors,
  System.Generics.Collections, FMX.Types, FMX.Types3D, FMX.Graphics,
  FireLinux.VulkanApi, FireLinux.VulkanDevice;

type
  TVulkanLight = record
    Opts, Pos, Dir, Color: TVector3D;
  end;

  TVulkanUniforms = record
    MVP, Model, NormalMatrix: TMatrix3D;
    Color, Diffuse, Specular, Ambient, Emission, Options, Eye, OpacityMod, Params: TVector3D;
    Lights: array[0..7] of TVulkanLight;
  end;

  TVulkanContext = class(TContext3D)
  private
    FCmd: VkCommandBuffer;
    FDeviceLocked: Boolean;
    FRenderPass: VkRenderPass;
    FFramebuffer: VkFramebuffer;
    FSamplers: array[0..3] of VkSampler;
    FSetLayout: VkDescriptorSetLayout;
    FPipelineLayout: VkPipelineLayout;
    FDescriptorPools: TList<VkDescriptorPool>;
    FPipelines: TDictionary<string, VkPipeline>;
    FResources: TObjectList<TVulkanBuffer>;
    FImageRefs: TList<IInterface>;
    FTargetRef: IInterface;
    FTarget, FDepth, FMultisample: TVulkanImage;
    FWhite: TVulkanImage;
    FReadback: TVulkanBuffer;
    FUniforms: TVulkanUniforms;
    FSampledTexture: TTexture;
    FStencil: VkStencilOpState;
    FVertexShader, FPixelShader: VkShaderModule;
    FPixelWidth, FPixelHeight, FSamples: Cardinal;
    FScissor: TRectF;
    function TextureSampler: VkSampler;
    function Pipeline(Kind: TPrimitivesKind): VkPipeline;
    function DescriptorSet(UniformBuffer: TVulkanBuffer; Image: TVulkanImage): VkDescriptorSet;
    procedure ReleaseFrame;
  protected
    constructor CreateFromTexture(const ATexture: TTexture; const AMultisample: TMultisample; const ADepthStencil: Boolean); override;
    constructor CreateFromWindow(const AParent: TWindowHandle; const AWidth, AHeight: Single; const AMultisample: TMultisample; const ADepthStencil: Boolean); override;
    procedure DoCreateBuffer; override;
    procedure DoFreeBuffer; override;
    procedure DoResize; override;
    procedure DoCopyToBits(const Bits: Pointer; const Pitch: Integer; const ARect: TRect); override;
    function DoBeginScene: Boolean; override;
    procedure DoEndScene; override;
    procedure DoClear(const ATarget: TClearTargets; const AColor: TAlphaColor; const ADepth: Single; const AStencil: Cardinal); override;
    procedure DoSetContextState(AState: TContextState); override;
    procedure DoSetStencilOp(const Fail, ZFail, ZPass: TStencilOp); override;
    procedure DoSetStencilFunc(const Func: TStencilFunc; Ref, Mask: Cardinal); override;
    procedure DoSetScissorRect(const ScissorRect: TRectF); override;
    procedure DoDrawPrimitivesBatch(const AKind: TPrimitivesKind; const Vertices, Indices: Pointer; const VertexDeclaration: TVertexDeclaration; const VertexSize, VertexCount, IndexSize, IndexCount: Integer); override;
    class procedure DoInitializeTexture(const Texture: TTexture); override;
    class procedure DoFinalizeTexture(const Texture: TTexture); override;
    class procedure DoUpdateTexture(const Texture: TTexture; const Bits: Pointer; const Pitch: Integer); override;
    class procedure DoInitializeShader(const Shader: TContextShader); override;
    class procedure DoFinalizeShader(const Shader: TContextShader); override;
    procedure DoSetShaders(const VertexShader, PixelShader: TContextShader); override;
    procedure DoSetShaderVariable(const Name: string; const Data: array of TVector3D); overload; override;
    procedure DoSetShaderVariable(const Name: string; const Texture: TTexture); overload; override;
    procedure DoSetShaderVariable(const Name: string; const Matrix: TMatrix3D); overload; override;
    function GetIndexBufferSupport: TContext3D.TIndexBufferSupport; override;
  public
    destructor Destroy; override;
    class function Valid: Boolean; override;
    class function MaxTextureSize: Integer; override;
    class function TextureUnitCount: Integer; override;
    class function PixelFormat: TPixelFormat; override;
    class function Style: TContextStyles; override;
    property ActualSamples: Cardinal read FSamples;
  end;

// Select before creating any context, material or texture. Backend changes during
// rendering are intentionally unsupported: FMX texture/shader handles are global.
procedure RegisterVulkanContext;
// Custom shaders use the descriptor/vertex ABI documented in shaders/viewport.*.

procedure RegisterVulkanShader(const Shader: TContextShader; const SPIRV: array of Cardinal);

function VulkanRendererName: string;

implementation

uses
  System.Math, FMX.Materials, FMX.Platform;

{$I FireLinux.VulkanShaders.inc}

type
  TVulkanVertex = packed record
    Position, Normal: TPoint3D;
    Color: TVector3D;
    UV: TPointF;
  end;

  PVulkanVertex = ^TVulkanVertex;

  TVulkanContextService = class(TInterfacedObject, IFMXContextService)
  public
    procedure RegisterContextClasses;
    procedure UnregisterContextClasses;
  end;

var
  GVertexModule, GPixelModule: VkShaderModule;
  GCustomShaders: TDictionary<string, VkShaderModule>;

function ShaderKey(const Shader: TContextShader): string;
begin
  Result := IntToStr(Ord(Shader.Kind)) + ':' + Shader.Name;
end;

function NewShader(const Code: array of Cardinal): VkShaderModule;
var
  Info: VkShaderModuleCreateInfo;
begin
  if (Length(Code) < 5) or (Code[0] <> $07230203) then
    raise EContext3DException.Create('Vulkan: invalid SPIR-V shader');
  Info := Default(VkShaderModuleCreateInfo);
  Info.sType := VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
  Info.codeSize := Length(Code) * SizeOf(Cardinal);
  Info.pCode := @Code[0];
  Result := 0;
  CheckVk(vkCreateShaderModule(VulkanDevice.Handle, @Info, nil, @Result), 'create shader module');
end;

procedure InitShaders;
begin
  if GVertexModule = 0 then
    GVertexModule := NewShader(ViewportVertSPV);
  if GPixelModule = 0 then
    GPixelModule := NewShader(ViewportFragSPV);
end;

function VulkanRendererName: string;
begin
  Result := string(PAnsiChar(@VulkanDevice.Properties.deviceName[0]));
end;

procedure TVulkanContextService.RegisterContextClasses;
begin
  TContextManager.RegisterContext(TVulkanContext, True);
end;

procedure TVulkanContextService.UnregisterContextClasses;
begin
end;

procedure RegisterVulkanContext;
begin
  // Replace only the context service; retain the Wayland platform's other services.
  // This prevents FMX's lazy registration from loading the stock libGL renderer.
  TContextManager.UnInitialize;
  TPlatformServices.Current.RemovePlatformService(IFMXContextService);
  TPlatformServices.Current.AddPlatformService(IFMXContextService, TVulkanContextService.Create);
end;

procedure RegisterVulkanShader(const Shader: TContextShader; const SPIRV: array of Cardinal);
var
  Module: VkShaderModule;
begin
  if (Shader = nil) or (Shader.Handle <> 0) then
    raise EContext3DException.Create('Vulkan: register SPIR-V before initializing the shader');
  if GCustomShaders = nil then
    GCustomShaders := TDictionary<string, VkShaderModule>.Create;
  if GCustomShaders.ContainsKey(ShaderKey(Shader)) then
    raise EContext3DException.Create('Vulkan: shader already registered');
  Module := NewShader(SPIRV);
  GCustomShaders.Add(ShaderKey(Shader), Module);
end;

function TextureImage(const Texture: TTexture): TVulkanImage;
begin
  if Texture.Handle = 0 then
    Texture.Initialize;
  Result := TVulkanImage(Pointer(Texture.Handle));
end;

class function TVulkanContext.PixelFormat: TPixelFormat;
begin
  Result := TPixelFormat.BGRA;
end;

class function TVulkanContext.TextureUnitCount: Integer;
begin
  Result := 1;
end;

class function TVulkanContext.Style: TContextStyles;
begin
  Result := [];
end;

class function TVulkanContext.Valid: Boolean;
begin
  Result := VulkanDevice.Handle <> 0;
end;

class function TVulkanContext.MaxTextureSize: Integer;
begin
  Result := VulkanDevice.Properties.limits.maxImageDimension2D;
end;

function TVulkanContext.GetIndexBufferSupport: TContext3D.TIndexBufferSupport;
begin
  Result := TIndexBufferSupport.Int32;
end;

constructor TVulkanContext.CreateFromWindow(const AParent: TWindowHandle; const AWidth, AHeight: Single; const AMultisample: TMultisample; const ADepthStencil: Boolean);
begin
  inherited;
  raise EContext3DException.Create('Vulkan: use TViewport3D; native TForm3D presentation is not implemented');
end;

constructor TVulkanContext.CreateFromTexture(const ATexture: TTexture; const AMultisample: TMultisample; const ADepthStencil: Boolean);
var
  Info: VkDescriptorSetLayoutCreateInfo;
  Bindings: array[0..1] of VkDescriptorSetLayoutBinding;
  LayoutInfo: VkPipelineLayoutCreateInfo;
  WhitePixel: Cardinal;
begin
  inherited;
  FResources := TObjectList<TVulkanBuffer>.Create(True);
  FImageRefs := TList<IInterface>.Create;
  FDescriptorPools := TList<VkDescriptorPool>.Create;
  FPipelines := TDictionary<string, VkPipeline>.Create;
  FUniforms := Default(TVulkanUniforms);
  FUniforms.MVP := TMatrix3D.Identity;
  FUniforms.Model := TMatrix3D.Identity;
  FUniforms.NormalMatrix := TMatrix3D.Identity;
  FUniforms.Color := Vector3D(1, 1, 1, 1);
  FUniforms.Diffuse := FUniforms.Color;
  FUniforms.OpacityMod := Vector3D(1, 0, 0, 0);
  FStencil.compareOp := VK_COMPARE_OP_ALWAYS;
  FStencil.compareMask := High(Cardinal);
  FStencil.writeMask := High(Cardinal);
  FillChar(Bindings, SizeOf(Bindings), 0);
  Bindings[0].binding := 0;
  Bindings[0].descriptorType := VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
  Bindings[0].descriptorCount := 1;
  Bindings[0].stageFlags := VK_SHADER_STAGE_VERTEX_BIT or VK_SHADER_STAGE_FRAGMENT_BIT;
  Bindings[1].binding := 1;
  Bindings[1].descriptorType := VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
  Bindings[1].descriptorCount := 1;
  Bindings[1].stageFlags := VK_SHADER_STAGE_FRAGMENT_BIT;
  Info := Default(VkDescriptorSetLayoutCreateInfo);
  Info.sType := VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
  Info.bindingCount := 2;
  Info.pBindings := @Bindings[0];
  CheckVk(vkCreateDescriptorSetLayout(VulkanDevice.Handle, @Info, nil, @FSetLayout), 'create descriptor layout');
  LayoutInfo := Default(VkPipelineLayoutCreateInfo);
  LayoutInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
  LayoutInfo.setLayoutCount := 1;
  LayoutInfo.pSetLayouts := @FSetLayout;
  CheckVk(vkCreatePipelineLayout(VulkanDevice.Handle, @LayoutInfo, nil, @FPipelineLayout), 'create pipeline layout');
  InitShaders;
  FVertexShader := GVertexModule;
  FPixelShader := GPixelModule;
  FWhite := TVulkanImage.Create(1, 1, VK_FORMAT_B8G8R8A8_UNORM,
    VK_IMAGE_USAGE_TRANSFER_DST_BIT or VK_IMAGE_USAGE_SAMPLED_BIT, 1, VK_IMAGE_ASPECT_COLOR_BIT);
  WhitePixel := $FFFFFFFF;
  FWhite.Upload(@WhitePixel, 4);
  CreateBuffer;
end;

destructor TVulkanContext.Destroy;
var
  Sampler: VkSampler;
begin
  FreeBuffer;
  FWhite.Free;
  for Sampler in FSamplers do
    if Sampler <> 0 then
      vkDestroySampler(VulkanDevice.Handle, Sampler, nil);
  if FPipelineLayout <> 0 then
    vkDestroyPipelineLayout(VulkanDevice.Handle, FPipelineLayout, nil);
  if FSetLayout <> 0 then
    vkDestroyDescriptorSetLayout(VulkanDevice.Handle, FSetLayout, nil);
  FResources.Free;
  FImageRefs.Free;
  FDescriptorPools.Free;
  FPipelines.Free;
  // TContext3D.Destroy calls DoFreeBuffer again, which is idempotent.
  FResources := nil;
  FImageRefs := nil;
  FDescriptorPools := nil;
  FPipelines := nil;
  inherited;
end;

procedure TVulkanContext.DoCreateBuffer;
var
  Attachments: array[0..2] of VkAttachmentDescription;
  Views: array[0..2] of VkImageView;
  ColorRef, DepthRef, ResolveRef: VkAttachmentReference;
  Subpass: VkSubpassDescription;
  Info: VkRenderPassCreateInfo;
  FrameInfo: VkFramebufferCreateInfo;
  Dependencies: array[0..1] of VkSubpassDependency;
  Count, Requested: Cardinal;
begin
  DoFreeBuffer;
  if (Texture = nil) or (Texture.Width <= 0) or (Texture.Height <= 0) then
    Exit;
  FPixelWidth := Texture.Width;
  FPixelHeight := Texture.Height;
  FTarget := TextureImage(Texture);
  FTargetRef := FTarget as IInterface;
  case Multisample of
    TMultisample.TwoSamples:
      Requested := 2;
    TMultisample.FourSamples:
      Requested := 4;
  else
    Requested := 1;
  end;
  FSamples := VulkanDevice.SampleCount(Requested);
  FDepth := TVulkanImage.Create(FPixelWidth, FPixelHeight, VulkanDevice.DepthFormat,
    VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT, FSamples, VK_IMAGE_ASPECT_DEPTH_BIT or VK_IMAGE_ASPECT_STENCIL_BIT);
  FillChar(Attachments, SizeOf(Attachments), 0);
  Attachments[0].format := FTarget.Format;
  Attachments[0].samples := FSamples;
  Attachments[0].loadOp := VK_ATTACHMENT_LOAD_OP_LOAD;
  Attachments[0].storeOp := VK_ATTACHMENT_STORE_OP_STORE;
  Attachments[0].stencilLoadOp := VK_ATTACHMENT_LOAD_OP_DONT_CARE;
  Attachments[0].stencilStoreOp := VK_ATTACHMENT_STORE_OP_DONT_CARE;
  Attachments[0].initialLayout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
  Attachments[0].finalLayout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
  Attachments[1].format := FDepth.Format;
  Attachments[1].samples := FSamples;
  Attachments[1].loadOp := VK_ATTACHMENT_LOAD_OP_LOAD;
  Attachments[1].storeOp := VK_ATTACHMENT_STORE_OP_STORE;
  Attachments[1].stencilLoadOp := VK_ATTACHMENT_LOAD_OP_LOAD;
  Attachments[1].stencilStoreOp := VK_ATTACHMENT_STORE_OP_STORE;
  Attachments[1].initialLayout := VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
  Attachments[1].finalLayout := VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
  ColorRef.attachment := 0;
  ColorRef.layout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
  DepthRef.attachment := 1;
  DepthRef.layout := VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
  Subpass := Default(VkSubpassDescription);
  Subpass.pipelineBindPoint := VK_PIPELINE_BIND_POINT_GRAPHICS;
  Subpass.colorAttachmentCount := 1;
  Subpass.pColorAttachments := @ColorRef;
  Subpass.pDepthStencilAttachment := @DepthRef;
  Views[0] := FTarget.View;
  Views[1] := FDepth.View;
  Count := 2;
  if FSamples > 1 then
  begin
    FMultisample := TVulkanImage.Create(FPixelWidth, FPixelHeight, FTarget.Format,
      VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT, FSamples, VK_IMAGE_ASPECT_COLOR_BIT);
    Views[0] := FMultisample.View;
    Views[2] := FTarget.View;
    Attachments[2] := Attachments[0];
    Attachments[2].samples := 1;
    Attachments[2].loadOp := VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    ResolveRef.attachment := 2;
    ResolveRef.layout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    Subpass.pResolveAttachments := @ResolveRef;
    Count := 3;
  end;
  FillChar(Dependencies, SizeOf(Dependencies), 0);
  Dependencies[0].srcSubpass := VK_SUBPASS_EXTERNAL;
  Dependencies[0].dstSubpass := 0;
  Dependencies[0].srcStageMask := VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
  Dependencies[0].dstStageMask := VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT or
    VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT or VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT;
  Dependencies[0].srcAccessMask := VK_ACCESS_MEMORY_WRITE_BIT;
  Dependencies[0].dstAccessMask := VK_ACCESS_COLOR_ATTACHMENT_READ_BIT or VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
    or VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT or VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
  Dependencies[1].srcSubpass := 0;
  Dependencies[1].dstSubpass := VK_SUBPASS_EXTERNAL;
  Dependencies[1].srcStageMask := Dependencies[0].dstStageMask;
  Dependencies[1].dstStageMask := VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
  Dependencies[1].srcAccessMask := VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT or VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
  Dependencies[1].dstAccessMask := VK_ACCESS_MEMORY_READ_BIT;
  Info := Default(VkRenderPassCreateInfo);
  Info.sType := VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
  Info.attachmentCount := Count;
  Info.pAttachments := @Attachments[0];
  Info.subpassCount := 1;
  Info.pSubpasses := @Subpass;
  Info.dependencyCount := 2;
  Info.pDependencies := @Dependencies[0];
  CheckVk(vkCreateRenderPass(VulkanDevice.Handle, @Info, nil, @FRenderPass), 'create render pass');
  FrameInfo := Default(VkFramebufferCreateInfo);
  FrameInfo.sType := VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
  FrameInfo.renderPass := FRenderPass;
  FrameInfo.attachmentCount := Count;
  FrameInfo.pAttachments := @Views[0];
  FrameInfo.width := FPixelWidth;
  FrameInfo.height := FPixelHeight;
  FrameInfo.layers := 1;
  CheckVk(vkCreateFramebuffer(VulkanDevice.Handle, @FrameInfo, nil, @FFramebuffer), 'create framebuffer');
  FReadback := TVulkanBuffer.Create(UInt64(FPixelWidth) * FPixelHeight * 4, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
end;

procedure TVulkanContext.ReleaseFrame;
var
  Pool: VkDescriptorPool;
begin
  if FDescriptorPools <> nil then
  begin
    for Pool in FDescriptorPools do
      vkDestroyDescriptorPool(VulkanDevice.Handle, Pool, nil);
    FDescriptorPools.Clear;
  end;
  if FResources <> nil then
    FResources.Clear;
  if FImageRefs <> nil then
    FImageRefs.Clear;
end;

procedure TVulkanContext.DoFreeBuffer;
var
  P: VkPipeline;
begin
  if FCmd <> 0 then
  begin
    vkFreeCommandBuffers(VulkanDevice.Handle, VulkanDevice.Pool, 1, @FCmd);
    FCmd := 0;
  end;
  if FDeviceLocked then
  begin
    FDeviceLocked := False;
    TMonitor.Exit(VulkanDevice);
  end;
  ReleaseFrame;
  if FPipelines <> nil then
  begin
    for P in FPipelines.Values do
      vkDestroyPipeline(VulkanDevice.Handle, P, nil);
    FPipelines.Clear;
  end;
  if FFramebuffer <> 0 then
    vkDestroyFramebuffer(VulkanDevice.Handle, FFramebuffer, nil);
  if FRenderPass <> 0 then
    vkDestroyRenderPass(VulkanDevice.Handle, FRenderPass, nil);
  FFramebuffer := 0;
  FRenderPass := 0;
  FreeAndNil(FDepth);
  FreeAndNil(FMultisample);
  FreeAndNil(FReadback);
  FTarget := nil;
  FTargetRef := nil;
end;

procedure TVulkanContext.DoResize;
begin
  DoCreateBuffer;
end;

function TVulkanContext.DoBeginScene: Boolean;
var
  Info: VkRenderPassBeginInfo;
begin
  Result := FFramebuffer <> 0;
  if not Result then
    Exit;
  TMonitor.Enter(VulkanDevice);
  FDeviceLocked := True;
  try
    ReleaseFrame;
    FCmd := VulkanDevice.BeginCommands;
    FTarget.Barrier(FCmd, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);
    FDepth.Barrier(FCmd, VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL);
    if FMultisample <> nil then
      FMultisample.Barrier(FCmd, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);
    Info := Default(VkRenderPassBeginInfo);
    Info.sType := VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    Info.renderPass := FRenderPass;
    Info.framebuffer := FFramebuffer;
    Info.renderArea.extent.width := FPixelWidth;
    Info.renderArea.extent.height := FPixelHeight;
    vkCmdBeginRenderPass(FCmd, @Info, VK_SUBPASS_CONTENTS_INLINE);
    Result := inherited DoBeginScene;
  except
    if FCmd <> 0 then
      vkFreeCommandBuffers(VulkanDevice.Handle, VulkanDevice.Pool, 1, @FCmd);
    FCmd := 0;
    FDeviceLocked := False;
    TMonitor.Exit(VulkanDevice);
    raise;
  end;
end;

procedure TVulkanContext.DoEndScene;
var
  Region: VkBufferImageCopy;
  Barrier: VkBufferMemoryBarrier;
  Cmd: VkCommandBuffer;
begin
  vkCmdEndRenderPass(FCmd);
  FTarget.Barrier(FCmd, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
  Region := Default(VkBufferImageCopy);
  Region.imageSubresource.aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
  Region.imageSubresource.layerCount := 1;
  Region.imageExtent.width := FPixelWidth;
  Region.imageExtent.height := FPixelHeight;
  Region.imageExtent.depth := 1;
  vkCmdCopyImageToBuffer(FCmd, FTarget.Image, FTarget.Layout, FReadback.Buffer, 1, @Region);
  Barrier := Default(VkBufferMemoryBarrier);
  Barrier.sType := VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
  Barrier.srcAccessMask := VK_ACCESS_TRANSFER_WRITE_BIT;
  Barrier.dstAccessMask := VK_ACCESS_HOST_READ_BIT;
  Barrier.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  Barrier.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  Barrier.buffer := FReadback.Buffer;
  Barrier.size := FReadback.Size;
  vkCmdPipelineBarrier(FCmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_HOST_BIT, 0,
    0, nil, 1, @Barrier, 0, nil);
  FTarget.Barrier(FCmd, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
  Cmd := FCmd;
  FCmd := 0;
  try
    VulkanDevice.Submit(Cmd);
  finally
    ReleaseFrame;
    FDeviceLocked := False;
    TMonitor.Exit(VulkanDevice);
  end;
  inherited;
end;

procedure TVulkanContext.DoCopyToBits(const Bits: Pointer; const Pitch: Integer; const ARect: TRect);
var
  Y: Integer;
  R: TRect;
begin
  if (Bits = nil) or (FReadback = nil) then
    Exit;
  if FCmd <> 0 then
    raise EContext3DException.Create('Vulkan: readback requires EndScene');
  R := TRect.Intersect(ARect, Rect(0, 0, FPixelWidth, FPixelHeight));
  if R.IsEmpty then
    Exit;
  if Abs(Pitch) < R.Right * 4 then
    raise EContext3DException.Create('Vulkan: readback pitch is too small');
  for Y := 0 to R.Height - 1 do
    Move(PByte(NativeUInt(FReadback.Data) + (NativeUInt(R.Top + Y) * FPixelWidth + Cardinal(R.Left)) * 4)^,
      PByte(NativeInt(Bits) + NativeInt(R.Top + Y) * Pitch + NativeInt(R.Left) * 4)^, R.Width * 4);
end;

procedure TVulkanContext.DoClear(const ATarget: TClearTargets; const AColor: TAlphaColor; const ADepth: Single; const AStencil: Cardinal);
var
  Attachments: array[0..1] of VkClearAttachment;
  R: VkClearRect;
  Count: Cardinal;
  C: TAlphaColorF;
begin
  if FCmd = 0 then
    Exit;
  FillChar(Attachments, SizeOf(Attachments), 0);
  Count := 0;
  if TClearTarget.Color in ATarget then
  begin
    C := TAlphaColorF.Create(AColor);
    Attachments[Count].aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
    Attachments[Count].clearValue.color.float32[0] := C.R * C.A;
    Attachments[Count].clearValue.color.float32[1] := C.G * C.A;
    Attachments[Count].clearValue.color.float32[2] := C.B * C.A;
    Attachments[Count].clearValue.color.float32[3] := C.A;
    Inc(Count);
  end;
  if (TClearTarget.Depth in ATarget) or (TClearTarget.Stencil in ATarget) then
  begin
    if TClearTarget.Depth in ATarget then
      Attachments[Count].aspectMask := VK_IMAGE_ASPECT_DEPTH_BIT;
    if TClearTarget.Stencil in ATarget then
      Attachments[Count].aspectMask := Attachments[Count].aspectMask or VK_IMAGE_ASPECT_STENCIL_BIT;
    Attachments[Count].clearValue.depthStencil.depth := ADepth;
    Attachments[Count].clearValue.depthStencil.stencil := AStencil;
    Inc(Count);
  end;
  R := Default(VkClearRect);
  R.rect.extent.width := FPixelWidth;
  R.rect.extent.height := FPixelHeight;
  R.layerCount := 1;
  if Count <> 0 then
    vkCmdClearAttachments(FCmd, Count, @Attachments[0], 1, @R);
end;

procedure TVulkanContext.DoSetContextState(AState: TContextState);
begin
  // Pipeline() snapshots FMX's complete current state at each draw.
end;

procedure TVulkanContext.DoSetScissorRect(const ScissorRect: TRectF);
begin
  FScissor := ScissorRect;
end;

procedure TVulkanContext.DoSetStencilOp(const Fail, ZFail, ZPass: TStencilOp);
const
  Ops: array[TStencilOp] of Cardinal = (VK_STENCIL_OP_KEEP, VK_STENCIL_OP_ZERO,
    VK_STENCIL_OP_REPLACE, VK_STENCIL_OP_INCREMENT_AND_CLAMP, VK_STENCIL_OP_DECREMENT_AND_CLAMP, VK_STENCIL_OP_INVERT);
begin
  FStencil.failOp := Ops[Fail];
  FStencil.depthFailOp := Ops[ZFail];
  FStencil.passOp := Ops[ZPass];
end;

procedure TVulkanContext.DoSetStencilFunc(const Func: TStencilFunc; Ref, Mask: Cardinal);
const
  Ops: array[TStencilFunc] of Cardinal = (VK_COMPARE_OP_NEVER, VK_COMPARE_OP_LESS,
    VK_COMPARE_OP_LESS_OR_EQUAL, VK_COMPARE_OP_GREATER, VK_COMPARE_OP_GREATER_OR_EQUAL,
    VK_COMPARE_OP_EQUAL, VK_COMPARE_OP_NOT_EQUAL, VK_COMPARE_OP_ALWAYS);
begin
  FStencil.compareOp := Ops[Func];
  FStencil.reference := Ref;
  FStencil.compareMask := Mask;
end;

function TVulkanContext.Pipeline(Kind: TPrimitivesKind): VkPipeline;
var
  Info: VkGraphicsPipelineCreateInfo;
  Stages: array[0..1] of VkPipelineShaderStageCreateInfo;
  Binding: VkVertexInputBindingDescription;
  Attributes: array[0..3] of VkVertexInputAttributeDescription;
  VertexInfo: VkPipelineVertexInputStateCreateInfo;
  Assembly: VkPipelineInputAssemblyStateCreateInfo;
  ViewportInfo: VkPipelineViewportStateCreateInfo;
  Raster: VkPipelineRasterizationStateCreateInfo;
  MS: VkPipelineMultisampleStateCreateInfo;
  Depth: VkPipelineDepthStencilStateCreateInfo;
  Blend: VkPipelineColorBlendStateCreateInfo;
  ColorBlend: VkPipelineColorBlendAttachmentState;
  dynamic: VkPipelineDynamicStateCreateInfo;
  States: array[0..1] of Cardinal;
  Key: string;
  Flags, I: Integer;
begin
  Flags := 0;
  for I := Ord(Low(TContextState)) to Ord(High(TContextState)) do
    if CurrentStates[TContextState(I)] then
      Flags := Flags or (1 shl I);
  Key := IntToStr(Ord(Kind)) + ':' + IntToStr(Flags) + ':' +
    IntToStr(FStencil.failOp) + ':' + IntToStr(FStencil.passOp) + ':' + IntToStr(FStencil.depthFailOp) + ':' +
    IntToStr(FStencil.compareOp) + ':' + UIntToStr(FStencil.reference) + ':' + UIntToStr(FStencil.compareMask) + ':' +
    UIntToStr(FVertexShader) + ':' + UIntToStr(FPixelShader);
  if FPipelines.TryGetValue(Key, Result) then
    Exit;
  FillChar(Stages, SizeOf(Stages), 0);
  Stages[0].sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
  Stages[0].stage := VK_SHADER_STAGE_VERTEX_BIT;
  Stages[0].Module := FVertexShader;
  Stages[0].pName := PAnsiChar('main');
  Stages[1].sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
  Stages[1].stage := VK_SHADER_STAGE_FRAGMENT_BIT;
  Stages[1].Module := FPixelShader;
  Stages[1].pName := PAnsiChar('main');
  Binding := Default(VkVertexInputBindingDescription);
  Binding.stride := SizeOf(TVulkanVertex);
  Binding.inputRate := VK_VERTEX_INPUT_RATE_VERTEX;
  FillChar(Attributes, SizeOf(Attributes), 0);
  for I := 0 to 3 do
    Attributes[I].location := I;
  Attributes[0].format := VK_FORMAT_R32G32B32_SFLOAT;
  Attributes[0].offset := 0;
  Attributes[1].format := VK_FORMAT_R32G32B32_SFLOAT;
  Attributes[1].offset := 12;
  Attributes[2].format := VK_FORMAT_R32G32B32A32_SFLOAT;
  Attributes[2].offset := 24;
  Attributes[3].format := VK_FORMAT_R32G32_SFLOAT;
  Attributes[3].offset := 40;
  VertexInfo := Default(VkPipelineVertexInputStateCreateInfo);
  VertexInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
  VertexInfo.vertexBindingDescriptionCount := 1;
  VertexInfo.pVertexBindingDescriptions := @Binding;
  VertexInfo.vertexAttributeDescriptionCount := 4;
  VertexInfo.pVertexAttributeDescriptions := @Attributes[0];
  Assembly := Default(VkPipelineInputAssemblyStateCreateInfo);
  Assembly.sType := VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
  case Kind of
    TPrimitivesKind.Points:
      Assembly.topology := VK_PRIMITIVE_TOPOLOGY_POINT_LIST;
    TPrimitivesKind.Lines:
      Assembly.topology := VK_PRIMITIVE_TOPOLOGY_LINE_LIST;
  else
    Assembly.topology := VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
  end;
  ViewportInfo := Default(VkPipelineViewportStateCreateInfo);
  ViewportInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
  ViewportInfo.viewportCount := 1;
  ViewportInfo.scissorCount := 1;
  Raster := Default(VkPipelineRasterizationStateCreateInfo);
  Raster.sType := VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
  Raster.polygonMode := VK_POLYGON_MODE_FILL;
  Raster.lineWidth := 1;
  Raster.frontFace := VK_FRONT_FACE_CLOCKWISE;
  if CurrentStates[TContextState.csFrontFace] then
    Raster.cullMode := VK_CULL_MODE_BACK_BIT
  else if CurrentStates[TContextState.csBackFace] then
    Raster.cullMode := VK_CULL_MODE_FRONT_BIT;
  MS := Default(VkPipelineMultisampleStateCreateInfo);
  MS.sType := VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
  MS.rasterizationSamples := FSamples;
  Depth := Default(VkPipelineDepthStencilStateCreateInfo);
  Depth.sType := VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
  Depth.depthTestEnable := Ord(DepthStencil and CurrentStates[TContextState.csZTestOn]);
  Depth.depthWriteEnable := Ord(DepthStencil and CurrentStates[TContextState.csZWriteOn]);
  Depth.depthCompareOp := VK_COMPARE_OP_LESS_OR_EQUAL;
  Depth.stencilTestEnable := Ord(DepthStencil and CurrentStates[TContextState.csStencilOn]);
  Depth.front := FStencil;
  Depth.back := FStencil;
  ColorBlend := Default(VkPipelineColorBlendAttachmentState);
  ColorBlend.blendEnable := Ord(CurrentStates[TContextState.csAlphaBlendOn]);
  ColorBlend.srcColorBlendFactor := VK_BLEND_FACTOR_ONE;
  ColorBlend.dstColorBlendFactor := VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
  ColorBlend.colorBlendOp := VK_BLEND_OP_ADD;
  ColorBlend.srcAlphaBlendFactor := VK_BLEND_FACTOR_ONE;
  ColorBlend.dstAlphaBlendFactor := VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
  ColorBlend.alphaBlendOp := VK_BLEND_OP_ADD;
  if not CurrentStates[TContextState.csColorWriteOff] then
    ColorBlend.colorWriteMask := $F;
  Blend := Default(VkPipelineColorBlendStateCreateInfo);
  Blend.sType := VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
  Blend.attachmentCount := 1;
  Blend.pAttachments := @ColorBlend;
  States[0] := VK_DYNAMIC_STATE_VIEWPORT;
  States[1] := VK_DYNAMIC_STATE_SCISSOR;
  dynamic := Default(VkPipelineDynamicStateCreateInfo);
  dynamic.sType := VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
  dynamic.dynamicStateCount := 2;
  dynamic.pDynamicStates := @States[0];
  Info := Default(VkGraphicsPipelineCreateInfo);
  Info.sType := VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
  Info.stageCount := 2;
  Info.pStages := @Stages[0];
  Info.pVertexInputState := @VertexInfo;
  Info.pInputAssemblyState := @Assembly;
  Info.pViewportState := @ViewportInfo;
  Info.pRasterizationState := @Raster;
  Info.pMultisampleState := @MS;
  Info.pDepthStencilState := @Depth;
  Info.pColorBlendState := @Blend;
  Info.pDynamicState := @dynamic;
  Info.layout := FPipelineLayout;
  Info.renderPass := FRenderPass;
  Info.basePipelineIndex := -1;
  Result := 0;
  CheckVk(vkCreateGraphicsPipelines(VulkanDevice.Handle, 0, 1, @Info, nil, @Result), 'create graphics pipeline');
  FPipelines.Add(Key, Result);
end;

function TVulkanContext.TextureSampler: VkSampler;
var
  Index: Integer;
  Info: VkSamplerCreateInfo;
begin
  if FSampledTexture = nil then
    Exit(FWhite.Sampler);
  Index := Ord(FSampledTexture.MinFilter) * 2 + Ord(FSampledTexture.MagFilter);
  if FSamplers[Index] = 0 then
  begin
    Info := Default(VkSamplerCreateInfo);
    Info.sType := VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
    Info.minFilter := Ord(FSampledTexture.MinFilter);
    Info.magFilter := Ord(FSampledTexture.MagFilter);
    Info.mipmapMode := Ord(FSampledTexture.MinFilter);
    Info.addressModeU := VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    Info.addressModeV := VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    Info.addressModeW := VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    Info.maxLod := 1000;
    CheckVk(vkCreateSampler(VulkanDevice.Handle, @Info, nil, @FSamplers[Index]), 'create texture sampler');
  end;
  Result := FSamplers[Index];
end;

function TVulkanContext.DescriptorSet(UniformBuffer: TVulkanBuffer; Image: TVulkanImage): VkDescriptorSet;
var
  PoolInfo: VkDescriptorPoolCreateInfo;
  Sizes: array[0..1] of VkDescriptorPoolSize;
  Allocate: VkDescriptorSetAllocateInfo;
  Pool: VkDescriptorPool;
  Writes: array[0..1] of VkWriteDescriptorSet;
  BufferInfo: VkDescriptorBufferInfo;
  ImageInfo: VkDescriptorImageInfo;
begin
  // One pool per draw avoids invalidating descriptor sets already recorded in
  // this frame. All pools/buffers retire after the submission fence signals.
  FillChar(Sizes, SizeOf(Sizes), 0);
  Sizes[0].&type := VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
  Sizes[0].descriptorCount := 1;
  Sizes[1].&type := VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
  Sizes[1].descriptorCount := 1;
  PoolInfo := Default(VkDescriptorPoolCreateInfo);
  PoolInfo.sType := VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
  PoolInfo.maxSets := 1;
  PoolInfo.poolSizeCount := 2;
  PoolInfo.pPoolSizes := @Sizes[0];
  Pool := 0;
  CheckVk(vkCreateDescriptorPool(VulkanDevice.Handle, @PoolInfo, nil, @Pool), 'create descriptor pool');
  FDescriptorPools.Add(Pool);
  Allocate := Default(VkDescriptorSetAllocateInfo);
  Allocate.sType := VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
  Allocate.descriptorPool := Pool;
  Allocate.descriptorSetCount := 1;
  Allocate.pSetLayouts := @FSetLayout;
  CheckVk(vkAllocateDescriptorSets(VulkanDevice.Handle, @Allocate, @Result), 'allocate descriptor set');
  BufferInfo := Default(VkDescriptorBufferInfo);
  BufferInfo.buffer := UniformBuffer.Buffer;
  BufferInfo.range := SizeOf(TVulkanUniforms);
  ImageInfo := Default(VkDescriptorImageInfo);
  ImageInfo.sampler := TextureSampler;
  ImageInfo.imageView := Image.View;
  ImageInfo.imageLayout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
  FillChar(Writes, SizeOf(Writes), 0);
  Writes[0].sType := VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
  Writes[0].dstSet := Result;
  Writes[0].dstBinding := 0;
  Writes[0].descriptorType := VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
  Writes[0].descriptorCount := 1;
  Writes[0].pBufferInfo := @BufferInfo;
  Writes[1].sType := VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
  Writes[1].dstSet := Result;
  Writes[1].dstBinding := 1;
  Writes[1].descriptorType := VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
  Writes[1].descriptorCount := 1;
  Writes[1].pImageInfo := @ImageInfo;
  vkUpdateDescriptorSets(VulkanDevice.Handle, 2, @Writes[0], 0, nil);
end;

procedure TVulkanContext.DoDrawPrimitivesBatch(const AKind: TPrimitivesKind; const Vertices, Indices: Pointer; const VertexDeclaration: TVertexDeclaration; const VertexSize, VertexCount, IndexSize, IndexCount: Integer);
var
  VB, IB, UB: TVulkanBuffer;
  V: PVulkanVertex;
  Source, Attribute: Pointer;
  Element: TVertexElement;
  I: Integer;
  Offset: UInt64;
  Image: TVulkanImage;
  SetHandle: VkDescriptorSet;
  Viewport: VkViewport;
  Scissor: VkRect2D;
  R: TRect;
  C: TAlphaColorF;
  IndexType: Cardinal;
begin
  if (VertexCount <= 0) or (IndexCount <= 0) then
    Exit;
  if FCmd = 0 then
    raise EContext3DException.Create('Vulkan: draw requires BeginScene');
  if not (IndexSize in [2, 4]) then
    raise EContext3DException.Create('Vulkan: unsupported index size');
  VB := TVulkanBuffer.Create(UInt64(VertexCount) * SizeOf(TVulkanVertex), VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
  FResources.Add(VB);
  V := PVulkanVertex(VB.Data);
  for I := 0 to VertexCount - 1 do
  begin
    V^ := Default(TVulkanVertex);
    V.Normal := Point3D(0, 0, -1);
    V.Color := Vector3D(1, 1, 1, 1);
    Source := PByte(NativeUInt(Vertices) + NativeUInt(I) * Cardinal(VertexSize));
    for Element in VertexDeclaration do
    begin
      Attribute := PByte(NativeUInt(Source) + Cardinal(Element.Offset));
      case Element.Format of
        TVertexFormat.Vertex:
          Move(Attribute^, V.Position, SizeOf(TPoint3D));
        TVertexFormat.Normal:
          Move(Attribute^, V.Normal, SizeOf(TPoint3D));
        TVertexFormat.TexCoord0:
          Move(Attribute^, V.UV, SizeOf(TPointF));
        TVertexFormat.Color0:
          begin
            C := TAlphaColorF.Create(PCardinal(Attribute)^);
            V.Color := Vector3D(C.R, C.G, C.B, C.A);
          end;
        TVertexFormat.ColorF0:
          Move(Attribute^, V.Color, SizeOf(TVector3D));
      end;
    end;
    Inc(V);
  end;
  IB := TVulkanBuffer.Create(UInt64(IndexCount) * Cardinal(IndexSize), VK_BUFFER_USAGE_INDEX_BUFFER_BIT);
  FResources.Add(IB);
  Move(Indices^, IB.Data^, IB.Size);
  Image := FWhite;
  FUniforms.Params.Y := 0;
  if FSampledTexture <> nil then
  begin
    Image := TextureImage(FSampledTexture);
    if Image = FTarget then
      raise EContext3DException.Create('Vulkan: cannot sample the active render target');
    if Image.Layout <> VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL then
      raise EContext3DException.Create('Vulkan: sampled texture has not been uploaded or rendered');
    FImageRefs.Add(Image as IInterface);
    FUniforms.Params.Y := 1;
  end;
  UB := TVulkanBuffer.Create(SizeOf(TVulkanUniforms), VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
  FResources.Add(UB);
  Move(FUniforms, UB.Data^, SizeOf(FUniforms));
  SetHandle := DescriptorSet(UB, Image);
  vkCmdBindPipeline(FCmd, VK_PIPELINE_BIND_POINT_GRAPHICS, Pipeline(AKind));
  Viewport := Default(VkViewport);
  Viewport.width := FPixelWidth;
  Viewport.height := FPixelHeight;
  Viewport.maxDepth := 1;
  vkCmdSetViewport(FCmd, 0, 1, @Viewport);
  R := Rect(0, 0, FPixelWidth, FPixelHeight);
  if CurrentStates[TContextState.csScissorOn] then
    R := TRect.Intersect(R, Rect(Floor(FScissor.Left * Scale), Floor(FScissor.Top * Scale),
        Ceil(FScissor.Right * Scale), Ceil(FScissor.Bottom * Scale)));
  if R.IsEmpty then
    Exit;
  Scissor := Default(VkRect2D);
  Scissor.offset.x := R.Left;
  Scissor.offset.y := R.Top;
  Scissor.extent.width := R.Width;
  Scissor.extent.height := R.Height;
  vkCmdSetScissor(FCmd, 0, 1, @Scissor);
  Offset := 0;
  vkCmdBindVertexBuffers(FCmd, 0, 1, @VB.Buffer, @Offset);
  if IndexSize = 2 then
    IndexType := VK_INDEX_TYPE_UINT16
  else
    IndexType := VK_INDEX_TYPE_UINT32;
  vkCmdBindIndexBuffer(FCmd, IB.Buffer, 0, IndexType);
  vkCmdBindDescriptorSets(FCmd, VK_PIPELINE_BIND_POINT_GRAPHICS, FPipelineLayout, 0, 1, @SetHandle, 0, nil);
  vkCmdDrawIndexed(FCmd, IndexCount, 1, 0, 0, 0);
end;

class procedure TVulkanContext.DoInitializeTexture(const Texture: TTexture);
var
  Image: TVulkanImage;
  Levels, Dimension: Cardinal;
  Features: VkFormatProperties;
begin
  if Texture.Handle <> 0 then
    Exit;
  if Texture.PixelFormat <> TPixelFormat.BGRA then
    raise EContext3DException.Create('Vulkan: texture pixel format must be BGRA');
  if (Texture.Width <= 0) or (Texture.Height <= 0) then
    Exit;
  Levels := 1;
  if (TTextureStyle.MipMaps in Texture.Style) and not (TTextureStyle.RenderTarget in Texture.Style) then
  begin
    vkGetPhysicalDeviceFormatProperties(VulkanDevice.Physical, VK_FORMAT_B8G8R8A8_UNORM, @Features);
    if (Features.optimalTilingFeatures and (VK_FORMAT_FEATURE_BLIT_SRC_BIT or
      VK_FORMAT_FEATURE_BLIT_DST_BIT or VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT)) =
      (VK_FORMAT_FEATURE_BLIT_SRC_BIT or VK_FORMAT_FEATURE_BLIT_DST_BIT or VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT) then
    begin
      Dimension := Max(Texture.Width, Texture.Height);
      while Dimension > 1 do
      begin
        Inc(Levels);
        Dimension := Dimension shr 1;
      end;
    end;
  end;
  Image := TVulkanImage.Create(Texture.Width, Texture.Height, VK_FORMAT_B8G8R8A8_UNORM,
    VK_IMAGE_USAGE_TRANSFER_SRC_BIT or VK_IMAGE_USAGE_TRANSFER_DST_BIT or VK_IMAGE_USAGE_SAMPLED_BIT
    or VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT, 1, VK_IMAGE_ASPECT_COLOR_BIT, Levels);
  Image.Retain; // FMX's opaque texture handle owns one interface reference.
  FMX.Types3D.ITextureAccess(Texture).Handle := TTextureHandle(Image);
end;

class procedure TVulkanContext.DoFinalizeTexture(const Texture: TTexture);
var
  Image: TVulkanImage;
begin
  if Texture.Handle = 0 then
    Exit;
  Image := TVulkanImage(Pointer(Texture.Handle));
  FMX.Types3D.ITextureAccess(Texture).Handle := 0;
  Image.Release;
end;

class procedure TVulkanContext.DoUpdateTexture(const Texture: TTexture; const Bits: Pointer; const Pitch: Integer);
var
  Image: TVulkanImage;
begin
  if Bits = nil then
    Exit;
  // Replace instead of mutating an image referenced by earlier draws in a frame.
  // Per-draw interface references keep the previous image alive through its fence.
  DoFinalizeTexture(Texture);
  DoInitializeTexture(Texture);
  Image := TextureImage(Texture);
  Image.Upload(Bits, Pitch);
end;

function IsBuiltinShader(const Shader: TContextShader): Boolean;
var
  Name: string;
begin
  Name := Shader.Name.ToLower;
  if Shader.Kind = TContextShaderKind.VertexShader then
    Result := (Name = 'color.fvs') or (Name = 'texture.fvs') or (Name = 'nolight.fvs') or
      (Name = 'gouraud1.fvs') or (Name = 'gouraud2.fvs') or (Name = 'gouraud4.fvs') or (Name = 'gouraud8.fvs')
  else
    Result := (Name = 'color.fps') or (Name = 'texture.fps') or (Name = 'texture_flip.fps') or
      (Name = 'gouraud.fps') or (Name = 'gouraud_flip.fps');
end;

class procedure TVulkanContext.DoInitializeShader(const Shader: TContextShader);
begin
  if not IsBuiltinShader(Shader) and ((GCustomShaders = nil) or not GCustomShaders.ContainsKey(ShaderKey(Shader))) then
    raise EContext3DException.CreateFmt('Vulkan: shader "%s" needs SPIR-V registered with RegisterVulkanShader', [Shader.Name]);
  Shader.Handle := 1;
end;

class procedure TVulkanContext.DoFinalizeShader(const Shader: TContextShader);
begin
  Shader.Handle := 0;
end;

procedure TVulkanContext.DoSetShaders(const VertexShader, PixelShader: TContextShader);
begin
  InitShaders;
  FVertexShader := GVertexModule;
  FPixelShader := GPixelModule;
  if VertexShader <> nil then
  begin
    if GCustomShaders <> nil then
      GCustomShaders.TryGetValue(ShaderKey(VertexShader), FVertexShader);
    if FVertexShader = 0 then
      FVertexShader := GVertexModule;
  end;
  if PixelShader <> nil then
  begin
    if GCustomShaders <> nil then
      GCustomShaders.TryGetValue(ShaderKey(PixelShader), FPixelShader);
    if FPixelShader = 0 then
      FPixelShader := GPixelModule;
    if PixelShader.Name.StartsWith('color.') then
      FUniforms.Params.X := 0
    else if PixelShader.Name.StartsWith('texture') then
      FUniforms.Params.X := 1
    else
      FUniforms.Params.X := 2;
    FUniforms.Params.Z := Ord(PixelShader.Name.Contains('_flip'));
  end;
  FSampledTexture := nil;
  FillChar(FUniforms.Lights, SizeOf(FUniforms.Lights), 0);
end;

procedure TVulkanContext.DoSetShaderVariable(const Name: string; const Matrix: TMatrix3D);
begin
  // Delphi matrices store row vectors; the same bytes form the transposed,
  // column-vector GLSL mat4. No extra CPU transpose is necessary.
  if Name = 'MVPMatrix' then
    FUniforms.MVP := Matrix
  else if Name = 'ModelView' then
    FUniforms.Model := Matrix
  else if Name = 'ModelViewIT' then
    FUniforms.NormalMatrix := Matrix
  else
    raise EContext3DException.Create('Vulkan: unknown matrix uniform ' + Name);
end;

procedure TVulkanContext.DoSetShaderVariable(const Name: string; const Texture: TTexture);
begin
  if Name <> 'texture0' then
    raise EContext3DException.Create('Vulkan: unknown texture uniform ' + Name);
  FSampledTexture := Texture;
end;

procedure TVulkanContext.DoSetShaderVariable(const Name: string; const Data: array of TVector3D);
var
  Value: TVector3D;
  Index, Closing: Integer;
  Field: string;
begin
  if Length(Data) = 0 then
    Exit;
  Value := Data[0];
  if Name = 'VulkanParams' then
    FUniforms.Params := Value
  else if Name = 'MaterialColor' then
    FUniforms.Color := Value
  else if Name = 'MaterialDiffuse' then
    FUniforms.Diffuse := Value
  else if Name = 'MaterialSpecular' then
    FUniforms.Specular := Value
  else if Name = 'MaterialAmbient' then
    FUniforms.Ambient := Value
  else if Name = 'MaterialEmission' then
    FUniforms.Emission := Value
  else if Name = 'MaterialOpts' then
    FUniforms.Options := Value
  else if Name = 'EyePos' then
    FUniforms.Eye := Value
  else if Name = 'Opacity' then
    FUniforms.OpacityMod.X := Value.X
  else if Name = 'Modulation' then
    FUniforms.OpacityMod.Y := Value.X
  else if Name.StartsWith('Lights[') then
  begin
    Closing := Name.IndexOf(']');
    Index := StrToIntDef(Name.Substring(7, Closing - 7), -1);
    if (Index < 0) or (Index > 7) then
      raise EContext3DException.Create('Vulkan: invalid light uniform ' + Name);
    Field := Name.Substring(Closing + 2);
    if Field = 'Opts' then
      FUniforms.Lights[Index].Opts := Value
    else if Field = 'Pos' then
      FUniforms.Lights[Index].Pos := Value
    else if Field = 'Dir' then
      FUniforms.Lights[Index].Dir := Value
    else if Field = 'Color' then
      FUniforms.Lights[Index].Color := Value
    else
      raise EContext3DException.Create('Vulkan: invalid light uniform ' + Name);
  end
  else
    raise EContext3DException.Create('Vulkan: unknown vector uniform ' + Name);
end;

procedure FreeShaders;
var
  Module: VkShaderModule;
begin
  if GCustomShaders <> nil then
  begin
    for Module in GCustomShaders.Values do
      vkDestroyShaderModule(VulkanDevice.Handle, Module, nil);
    FreeAndNil(GCustomShaders);
  end;
  if GVertexModule <> 0 then
    vkDestroyShaderModule(VulkanDevice.Handle, GVertexModule, nil);
  if GPixelModule <> 0 then
    vkDestroyShaderModule(VulkanDevice.Handle, GPixelModule, nil);
end;

initialization

finalization
  FreeShaders;

end.

