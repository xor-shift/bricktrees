pub const RequestAdapterStatus = enum(c_uint) {
    Success = 0x00000000,
    Unavailable = 0x00000001,
    Error = 0x00000002,
    Unknown = 0x00000003,
}; // RequestAdapterStatus

pub const AdapterType = enum(c_uint) {
    DiscreteGPU = 0x00000000,
    IntegratedGPU = 0x00000001,
    CPU = 0x00000002,
    Unknown = 0x00000003,
}; // AdapterType

pub const AddressMode = enum(c_uint) {
    Repeat = 0x00000000,
    MirrorRepeat = 0x00000001,
    ClampToEdge = 0x00000002,
}; // AddressMode

pub const BackendType = enum(c_uint) {
    Undefined = 0x00000000,
    Null = 0x00000001,
    WebGPU = 0x00000002,
    D3D11 = 0x00000003,
    D3D12 = 0x00000004,
    Metal = 0x00000005,
    Vulkan = 0x00000006,
    OpenGL = 0x00000007,
    OpenGLES = 0x00000008,
}; // BackendType

pub const BufferBindingType = enum(c_uint) {
    Undefined = 0x00000000,
    Uniform = 0x00000001,
    Storage = 0x00000002,
    ReadOnlyStorage = 0x00000003,
}; // BufferBindingType

pub const SamplerBindingType = enum(c_uint) {
    Undefined = 0x00000000,
    Filtering = 0x00000001,
    NonFiltering = 0x00000002,
    Comparison = 0x00000003,
}; // SamplerBindingType

pub const TextureSampleType = enum(c_uint) {
    Undefined = 0x00000000,
    Float = 0x00000001,
    UnfilterableFloat = 0x00000002,
    Depth = 0x00000003,
    Sint = 0x00000004,
    Uint = 0x00000005,
}; // TextureSampleType

pub const StorageTextureAccess = enum(c_uint) {
    Undefined = 0x00000000,
    WriteOnly = 0x00000001,
    ReadOnly = 0x00000002,
    ReadWrite = 0x00000003,
}; // StorageTextureAccess

pub const BlendFactor = enum(c_uint) {
    Zero = 0x00000000,
    One = 0x00000001,
    Src = 0x00000002,
    OneMinusSrc = 0x00000003,
    SrcAlpha = 0x00000004,
    OneMinusSrcAlpha = 0x00000005,
    Dst = 0x00000006,
    OneMinusDst = 0x00000007,
    DstAlpha = 0x00000008,
    OneMinusDstAlpha = 0x00000009,
    SrcAlphaSaturated = 0x0000000A,
    Constant = 0x0000000B,
    OneMinusConstant = 0x0000000C,
}; // BlendFactor

pub const BlendOperation = enum(c_uint) {
    Add = 0x00000000,
    Subtract = 0x00000001,
    ReverseSubtract = 0x00000002,
    Min = 0x00000003,
    Max = 0x00000004,
}; // BlendOperation

pub const BufferMapAsyncStatus = enum(c_uint) {
    Success = 0x00000000,
    ValidationError = 0x00000001,
    Unknown = 0x00000002,
    DeviceLost = 0x00000003,
    DestroyedBeforeCallback = 0x00000004,
    UnmappedBeforeCallback = 0x00000005,
    MappingAlreadyPending = 0x00000006,
    OffsetOutOfRange = 0x00000007,
    SizeOutOfRange = 0x00000008,
}; // BufferMapAsyncStatus

pub const BufferMapState = enum(c_uint) {
    Unmapped = 0x00000000,
    Pending = 0x00000001,
    Mapped = 0x00000002,
}; // BufferMapState

pub const CompareFunction = enum(c_uint) {
    Undefined = 0x00000000,
    Never = 0x00000001,
    Less = 0x00000002,
    LessEqual = 0x00000003,
    Greater = 0x00000004,
    GreaterEqual = 0x00000005,
    Equal = 0x00000006,
    NotEqual = 0x00000007,
    Always = 0x00000008,
}; // CompareFunction

pub const CompilationInfoRequestStatus = enum(c_uint) {
    Success = 0x00000000,
    Error = 0x00000001,
    DeviceLost = 0x00000002,
    Unknown = 0x00000003,
}; // CompilationInfoRequestStatus

pub const CompilationMessageType = enum(c_uint) {
    Error = 0x00000000,
    Warning = 0x00000001,
    Info = 0x00000002,
}; // CompilationMessageType

pub const CompositeAlphaMode = enum(c_uint) {
    Auto = 0x00000000,
    Opaque = 0x00000001,
    Premultiplied = 0x00000002,
    Unpremultiplied = 0x00000003,
    Inherit = 0x00000004,
}; // CompositeAlphaMode

pub const CreatePipelineAsyncStatus = enum(c_uint) {
    Success = 0x00000000,
    ValidationError = 0x00000001,
    InternalError = 0x00000002,
    DeviceLost = 0x00000003,
    DeviceDestroyed = 0x00000004,
    Unknown = 0x00000005,
}; // CreatePipelineAsyncStatus

pub const CullMode = enum(c_uint) {
    None = 0x00000000,
    Front = 0x00000001,
    Back = 0x00000002,
}; // CullMode

pub const DeviceLostReason = enum(c_uint) {
    Unknown = 0x00000000,
    Destroyed = 0x00000001,
}; // DeviceLostReason

pub const ErrorFilter = enum(c_uint) {
    Validation = 0x00000000,
    OutOfMemory = 0x00000001,
    Internal = 0x00000002,
}; // ErrorFilter

pub const ErrorType = enum(c_uint) {
    NoError = 0x00000000,
    Validation = 0x00000001,
    OutOfMemory = 0x00000002,
    Internal = 0x00000003,
    Unknown = 0x00000004,
    DeviceLost = 0x00000005,
}; // ErrorType

pub const FeatureName = enum(c_uint) {
    Undefined = 0x00000000,
    DepthClipControl = 0x00000001,
    Depth32FloatStencil8 = 0x00000002,
    TimestampQuery = 0x00000003,
    TextureCompressionBC = 0x00000004,
    TextureCompressionETC2 = 0x00000005,
    TextureCompressionASTC = 0x00000006,
    IndirectFirstInstance = 0x00000007,
    ShaderF16 = 0x00000008,
    RG11B10UfloatRenderable = 0x00000009,
    BGRA8UnormStorage = 0x0000000A,
    Float32Filterable = 0x0000000B,
    PushConstants = 0x00030001,
    TextureAdapterSpecificFormatFeatures = 0x00030002,
    MultiDrawIndirect = 0x00030003,
    MultiDrawIndirectCount = 0x00030004,
    VertexWritableStorage = 0x00030005,
    TextureBindingArray = 0x00030006,
    SampledTextureAndStorageBufferArrayNonUniformIndexing = 0x00030007,
    PipelineStatisticsQuery = 0x00030008,
    StorageResourceBindingArray = 0x00030009,
    PartiallyBoundBindingArray = 0x0003000A,
    TextureFormat16bitNorm = 0x0003000B,
    TextureCompressionAstcHdr = 0x0003000C,
    Reserved3000D = 0x0003000D,
    MappablePrimaryBuffers = 0x0003000E,
    BufferBindingArray = 0x0003000F,
    UniformBufferAndStorageTextureArrayNonUniformIndexing = 0x00030010,
    AddressModeClampToZero = 0x00030011,
    AddressModeClampToBorder = 0x00030012,
    PolygonModeLine = 0x00030013,
    PolygonModePoint = 0x00030014,
    ConservativeRasterization = 0x00030015,
    ClearTexture = 0x00030016,
    SpirvShaderPassthrough = 0x00030017,
    Multiview = 0x00030018,
    VertexAttribute64bit = 0x00030019,
    TextureFormatNv12 = 0x0003001A,
    RayTracingAccelerationStructure = 0x0003001B,
    RayQuery = 0x0003001C,
    ShaderF64 = 0x0003001D,
    ShaderI16 = 0x0003001E,
    ShaderPrimitiveIndex = 0x0003001F,
    ShaderEarlyDepthTest = 0x00030020,
    Subgroup = 0x00030021,
    SubgroupVertex = 0x00030022,
    SubgroupBarrier = 0x00030023,
    TimestampQueryInsideEncoders = 0x00030024,
    TimestampQueryInsidePasses = 0x00030025,
}; // FeatureName

pub const FilterMode = enum(c_uint) {
    Nearest = 0x00000000,
    Linear = 0x00000001,
}; // FilterMode

pub const FrontFace = enum(c_uint) {
    CCW = 0x00000000,
    CW = 0x00000001,
}; // FrontFace

pub const IndexFormat = enum(c_uint) {
    Undefined = 0x00000000,
    Uint16 = 0x00000001,
    Uint32 = 0x00000002,
}; // IndexFormat

pub const VertexStepMode = enum(c_uint) {
    Vertex = 0x00000000,
    Instance = 0x00000001,
    VertexBufferNotUsed = 0x00000002,
}; // VertexStepMode

pub const LoadOp = enum(c_uint) {
    Undefined = 0x00000000,
    Clear = 0x00000001,
    Load = 0x00000002,
}; // LoadOp

pub const MipmapFilterMode = enum(c_uint) {
    Nearest = 0x00000000,
    Linear = 0x00000001,
}; // MipmapFilterMode

pub const StoreOp = enum(c_uint) {
    Undefined = 0x00000000,
    Store = 0x00000001,
    Discard = 0x00000002,
}; // StoreOp

pub const PowerPreference = enum(c_uint) {
    Undefined = 0x00000000,
    LowPower = 0x00000001,
    HighPerformance = 0x00000002,
}; // PowerPreference

pub const PresentMode = enum(c_uint) {
    Fifo = 0x00000000,
    FifoRelaxed = 0x00000001,
    Immediate = 0x00000002,
    Mailbox = 0x00000003,
}; // PresentMode

pub const PrimitiveTopology = enum(c_uint) {
    PointList = 0x00000000,
    LineList = 0x00000001,
    LineStrip = 0x00000002,
    TriangleList = 0x00000003,
    TriangleStrip = 0x00000004,
}; // PrimitiveTopology

pub const QueryType = enum(c_uint) {
    Occlusion = 0x00000000,
    Timestamp = 0x00000001,
    PipelineStatistics = 0x00030001,
}; // QueryType

pub const QueueWorkDoneStatus = enum(c_uint) {
    Success = 0x00000000,
    Error = 0x00000001,
    Unknown = 0x00000002,
    DeviceLost = 0x00000003,
}; // QueueWorkDoneStatus

pub const RequestDeviceStatus = enum(c_uint) {
    Success = 0x00000000,
    Error = 0x00000001,
    Unknown = 0x00000002,
}; // RequestDeviceStatus

pub const StencilOperation = enum(c_uint) {
    Keep = 0x00000000,
    Zero = 0x00000001,
    Replace = 0x00000002,
    Invert = 0x00000003,
    IncrementClamp = 0x00000004,
    DecrementClamp = 0x00000005,
    IncrementWrap = 0x00000006,
    DecrementWrap = 0x00000007,
}; // StencilOperation

pub const SType = enum(c_uint) {
    Invalid = 0x00000000,
    SurfaceDescriptorFromMetalLayer = 0x00000001,
    SurfaceDescriptorFromWindowsHWND = 0x00000002,
    SurfaceDescriptorFromXlibWindow = 0x00000003,
    SurfaceDescriptorFromCanvasHTMLSelector = 0x00000004,
    ShaderModuleSPIRVDescriptor = 0x00000005,
    ShaderModuleWGSLDescriptor = 0x00000006,
    PrimitiveDepthClipControl = 0x00000007,
    SurfaceDescriptorFromWaylandSurface = 0x00000008,
    SurfaceDescriptorFromAndroidNativeWindow = 0x00000009,
    SurfaceDescriptorFromXcbWindow = 0x0000000A,
    RenderPassDescriptorMaxDrawCount = 0x0000000B,
    DeviceExtras = 0x00030001,
    RequiredLimitsExtras = 0x00030002,
    PipelineLayoutExtras = 0x00030003,
    ShaderModuleGLSLDescriptor = 0x00030004,
    SupportedLimitsExtras = 0x00030005,
    InstanceExtras = 0x00030006,
    BindGroupEntryExtras = 0x00030007,
    BindGroupLayoutEntryExtras = 0x00030008,
    QuerySetDescriptorExtras = 0x00030009,
    SurfaceConfigurationExtras = 0x0003000A,
}; // SType

pub const SurfaceGetCurrentTextureStatus = enum(c_uint) {
    Success = 0x00000000,
    Timeout = 0x00000001,
    Outdated = 0x00000002,
    Lost = 0x00000003,
    OutOfMemory = 0x00000004,
    DeviceLost = 0x00000005,
}; // SurfaceGetCurrentTextureStatus

pub const TextureAspect = enum(c_uint) {
    All = 0x00000000,
    StencilOnly = 0x00000001,
    DepthOnly = 0x00000002,
}; // TextureAspect

pub const TextureDimension = enum(c_uint) {
    D1 = 0x00000000,
    D2 = 0x00000001,
    D3 = 0x00000002,
}; // TextureDimension

pub const TextureFormat = enum(c_uint) {
    Undefined = 0x00000000,
    R8Unorm = 0x00000001,
    R8Snorm = 0x00000002,
    R8Uint = 0x00000003,
    R8Sint = 0x00000004,
    R16Uint = 0x00000005,
    R16Sint = 0x00000006,
    R16Float = 0x00000007,
    RG8Unorm = 0x00000008,
    RG8Snorm = 0x00000009,
    RG8Uint = 0x0000000A,
    RG8Sint = 0x0000000B,
    R32Float = 0x0000000C,
    R32Uint = 0x0000000D,
    R32Sint = 0x0000000E,
    RG16Uint = 0x0000000F,
    RG16Sint = 0x00000010,
    RG16Float = 0x00000011,
    RGBA8Unorm = 0x00000012,
    RGBA8UnormSrgb = 0x00000013,
    RGBA8Snorm = 0x00000014,
    RGBA8Uint = 0x00000015,
    RGBA8Sint = 0x00000016,
    BGRA8Unorm = 0x00000017,
    BGRA8UnormSrgb = 0x00000018,
    RGB10A2Uint = 0x00000019,
    RGB10A2Unorm = 0x0000001A,
    RG11B10Ufloat = 0x0000001B,
    RGB9E5Ufloat = 0x0000001C,
    RG32Float = 0x0000001D,
    RG32Uint = 0x0000001E,
    RG32Sint = 0x0000001F,
    RGBA16Uint = 0x00000020,
    RGBA16Sint = 0x00000021,
    RGBA16Float = 0x00000022,
    RGBA32Float = 0x00000023,
    RGBA32Uint = 0x00000024,
    RGBA32Sint = 0x00000025,
    Stencil8 = 0x00000026,
    Depth16Unorm = 0x00000027,
    Depth24Plus = 0x00000028,
    Depth24PlusStencil8 = 0x00000029,
    Depth32Float = 0x0000002A,
    Depth32FloatStencil8 = 0x0000002B,
    BC1RGBAUnorm = 0x0000002C,
    BC1RGBAUnormSrgb = 0x0000002D,
    BC2RGBAUnorm = 0x0000002E,
    BC2RGBAUnormSrgb = 0x0000002F,
    BC3RGBAUnorm = 0x00000030,
    BC3RGBAUnormSrgb = 0x00000031,
    BC4RUnorm = 0x00000032,
    BC4RSnorm = 0x00000033,
    BC5RGUnorm = 0x00000034,
    BC5RGSnorm = 0x00000035,
    BC6HRGBUfloat = 0x00000036,
    BC6HRGBFloat = 0x00000037,
    BC7RGBAUnorm = 0x00000038,
    BC7RGBAUnormSrgb = 0x00000039,
    ETC2RGB8Unorm = 0x0000003A,
    ETC2RGB8UnormSrgb = 0x0000003B,
    ETC2RGB8A1Unorm = 0x0000003C,
    ETC2RGB8A1UnormSrgb = 0x0000003D,
    ETC2RGBA8Unorm = 0x0000003E,
    ETC2RGBA8UnormSrgb = 0x0000003F,
    EACR11Unorm = 0x00000040,
    EACR11Snorm = 0x00000041,
    EACRG11Unorm = 0x00000042,
    EACRG11Snorm = 0x00000043,
    ASTC4x4Unorm = 0x00000044,
    ASTC4x4UnormSrgb = 0x00000045,
    ASTC5x4Unorm = 0x00000046,
    ASTC5x4UnormSrgb = 0x00000047,
    ASTC5x5Unorm = 0x00000048,
    ASTC5x5UnormSrgb = 0x00000049,
    ASTC6x5Unorm = 0x0000004A,
    ASTC6x5UnormSrgb = 0x0000004B,
    ASTC6x6Unorm = 0x0000004C,
    ASTC6x6UnormSrgb = 0x0000004D,
    ASTC8x5Unorm = 0x0000004E,
    ASTC8x5UnormSrgb = 0x0000004F,
    ASTC8x6Unorm = 0x00000050,
    ASTC8x6UnormSrgb = 0x00000051,
    ASTC8x8Unorm = 0x00000052,
    ASTC8x8UnormSrgb = 0x00000053,
    ASTC10x5Unorm = 0x00000054,
    ASTC10x5UnormSrgb = 0x00000055,
    ASTC10x6Unorm = 0x00000056,
    ASTC10x6UnormSrgb = 0x00000057,
    ASTC10x8Unorm = 0x00000058,
    ASTC10x8UnormSrgb = 0x00000059,
    ASTC10x10Unorm = 0x0000005A,
    ASTC10x10UnormSrgb = 0x0000005B,
    ASTC12x10Unorm = 0x0000005C,
    ASTC12x10UnormSrgb = 0x0000005D,
    ASTC12x12Unorm = 0x0000005E,
    ASTC12x12UnormSrgb = 0x0000005F,
    R16Unorm = 0x00030001,
    R16Snorm = 0x00030002,
    Rg16Unorm = 0x00030003,
    Rg16Snorm = 0x00030004,
    Rgba16Unorm = 0x00030005,
    Rgba16Snorm = 0x00030006,
    NV12 = 0x00030007,
}; // TextureFormat

pub const TextureViewDimension = enum(c_uint) {
    Undefined = 0x00000000,
    D1 = 0x00000001,
    D2 = 0x00000002,
    D2Array = 0x00000003,
    Cube = 0x00000004,
    CubeArray = 0x00000005,
    D3 = 0x00000006,
}; // TextureViewDimension

pub const VertexFormat = enum(c_uint) {
    Undefined = 0x00000000,
    Uint8x2 = 0x00000001,
    Uint8x4 = 0x00000002,
    Sint8x2 = 0x00000003,
    Sint8x4 = 0x00000004,
    Unorm8x2 = 0x00000005,
    Unorm8x4 = 0x00000006,
    Snorm8x2 = 0x00000007,
    Snorm8x4 = 0x00000008,
    Uint16x2 = 0x00000009,
    Uint16x4 = 0x0000000A,
    Sint16x2 = 0x0000000B,
    Sint16x4 = 0x0000000C,
    Unorm16x2 = 0x0000000D,
    Unorm16x4 = 0x0000000E,
    Snorm16x2 = 0x0000000F,
    Snorm16x4 = 0x00000010,
    Float16x2 = 0x00000011,
    Float16x4 = 0x00000012,
    Float32 = 0x00000013,
    Float32x2 = 0x00000014,
    Float32x3 = 0x00000015,
    Float32x4 = 0x00000016,
    Uint32 = 0x00000017,
    Uint32x2 = 0x00000018,
    Uint32x3 = 0x00000019,
    Uint32x4 = 0x0000001A,
    Sint32 = 0x0000001B,
    Sint32x2 = 0x0000001C,
    Sint32x3 = 0x0000001D,
    Sint32x4 = 0x0000001E,
}; // VertexFormat

pub const WGSLFeatureName = enum(c_uint) {
    Undefined = 0x00000000,
    ReadonlyAndReadwriteStorageTextures = 0x00000001,
    Packed4x8IntegerDotProduct = 0x00000002,
    UnrestrictedPointerParameters = 0x00000003,
    PointerCompositeAccess = 0x00000004,
}; // WGSLFeatureName
