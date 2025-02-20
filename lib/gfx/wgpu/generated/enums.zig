pub const AdapterType = enum(c_uint) {
    DiscreteGPU = 0x00000001,
    IntegratedGPU = 0x00000002,
    CPU = 0x00000003,
    Unknown = 0x00000004,
}; // AdapterType

pub const AddressMode = enum(c_uint) {
    Undefined = 0x00000000,
    ClampToEdge = 0x00000001,
    Repeat = 0x00000002,
    MirrorRepeat = 0x00000003,
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

pub const BlendFactor = enum(c_uint) {
    Undefined = 0x00000000,
    Zero = 0x00000001,
    One = 0x00000002,
    Src = 0x00000003,
    OneMinusSrc = 0x00000004,
    SrcAlpha = 0x00000005,
    OneMinusSrcAlpha = 0x00000006,
    Dst = 0x00000007,
    OneMinusDst = 0x00000008,
    DstAlpha = 0x00000009,
    OneMinusDstAlpha = 0x0000000A,
    SrcAlphaSaturated = 0x0000000B,
    Constant = 0x0000000C,
    OneMinusConstant = 0x0000000D,
    Src1 = 0x0000000E,
    OneMinusSrc1 = 0x0000000F,
    Src1Alpha = 0x00000010,
    OneMinusSrc1Alpha = 0x00000011,
}; // BlendFactor

pub const BlendOperation = enum(c_uint) {
    Undefined = 0x00000000,
    Add = 0x00000001,
    Subtract = 0x00000002,
    ReverseSubtract = 0x00000003,
    Min = 0x00000004,
    Max = 0x00000005,
}; // BlendOperation

pub const BufferBindingType = enum(c_uint) {
    BindingNotUsed = 0x00000000,
    Undefined = 0x00000001,
    Uniform = 0x00000002,
    Storage = 0x00000003,
    ReadOnlyStorage = 0x00000004,
}; // BufferBindingType

pub const BufferMapState = enum(c_uint) {
    Unmapped = 0x00000001,
    Pending = 0x00000002,
    Mapped = 0x00000003,
}; // BufferMapState

pub const CallbackMode = enum(c_uint) {
    WaitAnyOnly = 0x00000001,
    AllowProcessEvents = 0x00000002,
    AllowSpontaneous = 0x00000003,
}; // CallbackMode

pub const CompareFunction = enum(c_uint) {
    Undefined = 0x00000000,
    Never = 0x00000001,
    Less = 0x00000002,
    Equal = 0x00000003,
    LessEqual = 0x00000004,
    Greater = 0x00000005,
    NotEqual = 0x00000006,
    GreaterEqual = 0x00000007,
    Always = 0x00000008,
}; // CompareFunction

pub const CompilationInfoRequestStatus = enum(c_uint) {
    Success = 0x00000001,
    InstanceDropped = 0x00000002,
    Error = 0x00000003,
    Unknown = 0x00000004,
}; // CompilationInfoRequestStatus

pub const CompilationMessageType = enum(c_uint) {
    Error = 0x00000001,
    Warning = 0x00000002,
    Info = 0x00000003,
}; // CompilationMessageType

pub const CompositeAlphaMode = enum(c_uint) {
    Auto = 0x00000000,
    Opaque = 0x00000001,
    Premultiplied = 0x00000002,
    Unpremultiplied = 0x00000003,
    Inherit = 0x00000004,
}; // CompositeAlphaMode

pub const CreatePipelineAsyncStatus = enum(c_uint) {
    Success = 0x00000001,
    InstanceDropped = 0x00000002,
    ValidationError = 0x00000003,
    InternalError = 0x00000004,
    Unknown = 0x00000005,
}; // CreatePipelineAsyncStatus

pub const CullMode = enum(c_uint) {
    Undefined = 0x00000000,
    None = 0x00000001,
    Front = 0x00000002,
    Back = 0x00000003,
}; // CullMode

pub const DeviceLostReason = enum(c_uint) {
    Unknown = 0x00000001,
    Destroyed = 0x00000002,
    InstanceDropped = 0x00000003,
    FailedCreation = 0x00000004,
}; // DeviceLostReason

pub const ErrorFilter = enum(c_uint) {
    Validation = 0x00000001,
    OutOfMemory = 0x00000002,
    Internal = 0x00000003,
}; // ErrorFilter

pub const ErrorType = enum(c_uint) {
    NoError = 0x00000001,
    Validation = 0x00000002,
    OutOfMemory = 0x00000003,
    Internal = 0x00000004,
    Unknown = 0x00000005,
}; // ErrorType

pub const FeatureLevel = enum(c_uint) {
    Compatibility = 0x00000001,
    Core = 0x00000002,
}; // FeatureLevel

pub const FeatureName = enum(c_uint) {
    Undefined = 0x00000000,
    DepthClipControl = 0x00000001,
    Depth32FloatStencil8 = 0x00000002,
    TimestampQuery = 0x00000003,
    TextureCompressionBC = 0x00000004,
    TextureCompressionBCSliced3D = 0x00000005,
    TextureCompressionETC2 = 0x00000006,
    TextureCompressionASTC = 0x00000007,
    TextureCompressionASTCSliced3D = 0x00000008,
    IndirectFirstInstance = 0x00000009,
    ShaderF16 = 0x0000000A,
    RG11B10UfloatRenderable = 0x0000000B,
    BGRA8UnormStorage = 0x0000000C,
    Float32Filterable = 0x0000000D,
    Float32Blendable = 0x0000000E,
    ClipDistances = 0x0000000F,
    DualSourceBlending = 0x00000010,
    PushConstants = 0x00030000,
    TextureAdapterSpecificFormatFeatures = 0x00030001,
    MultiDrawIndirect = 0x00030002,
    MultiDrawIndirectCount = 0x00030003,
    VertexWritableStorage = 0x00030004,
    TextureBindingArray = 0x00030005,
    SampledTextureAndStorageBufferArrayNonUniformIndexing = 0x00030006,
    PipelineStatisticsQuery = 0x00030007,
    StorageResourceBindingArray = 0x00030008,
    PartiallyBoundBindingArray = 0x00030009,
    TextureFormat16bitNorm = 0x0003000A,
    TextureCompressionAstcHdr = 0x0003000B,
    Reserved3000D = 0x0003000C,
    MappablePrimaryBuffers = 0x0003000D,
    BufferBindingArray = 0x0003000E,
    UniformBufferAndStorageTextureArrayNonUniformIndexing = 0x0003000F,
    AddressModeClampToZero = 0x00030010,
    AddressModeClampToBorder = 0x00030011,
    PolygonModeLine = 0x00030012,
    PolygonModePoint = 0x00030013,
    ConservativeRasterization = 0x00030014,
    ClearTexture = 0x00030015,
    SpirvShaderPassthrough = 0x00030016,
    Multiview = 0x00030017,
    VertexAttribute64bit = 0x00030018,
    TextureFormatNv12 = 0x00030019,
    RayTracingAccelerationStructure = 0x0003001A,
    RayQuery = 0x0003001B,
    ShaderF64 = 0x0003001C,
    ShaderI16 = 0x0003001D,
    ShaderPrimitiveIndex = 0x0003001E,
    ShaderEarlyDepthTest = 0x0003001F,
    Subgroup = 0x00030020,
    SubgroupVertex = 0x00030021,
    SubgroupBarrier = 0x00030022,
    TimestampQueryInsideEncoders = 0x00030023,
    TimestampQueryInsidePasses = 0x00030024,
}; // FeatureName

pub const FilterMode = enum(c_uint) {
    Undefined = 0x00000000,
    Nearest = 0x00000001,
    Linear = 0x00000002,
}; // FilterMode

pub const FrontFace = enum(c_uint) {
    Undefined = 0x00000000,
    CCW = 0x00000001,
    CW = 0x00000002,
}; // FrontFace

pub const IndexFormat = enum(c_uint) {
    Undefined = 0x00000000,
    Uint16 = 0x00000001,
    Uint32 = 0x00000002,
}; // IndexFormat

pub const LoadOp = enum(c_uint) {
    Undefined = 0x00000000,
    Load = 0x00000001,
    Clear = 0x00000002,
}; // LoadOp

pub const MapAsyncStatus = enum(c_uint) {
    Success = 0x00000001,
    InstanceDropped = 0x00000002,
    Error = 0x00000003,
    Aborted = 0x00000004,
    Unknown = 0x00000005,
}; // MapAsyncStatus

pub const MipmapFilterMode = enum(c_uint) {
    Undefined = 0x00000000,
    Nearest = 0x00000001,
    Linear = 0x00000002,
}; // MipmapFilterMode

pub const OptionalBool = enum(c_uint) {
    False = 0x00000000,
    True = 0x00000001,
    Undefined = 0x00000002,
}; // OptionalBool

pub const PopErrorScopeStatus = enum(c_uint) {
    Success = 0x00000001,
    InstanceDropped = 0x00000002,
    EmptyStack = 0x00000003,
}; // PopErrorScopeStatus

pub const PowerPreference = enum(c_uint) {
    Undefined = 0x00000000,
    LowPower = 0x00000001,
    HighPerformance = 0x00000002,
}; // PowerPreference

pub const PresentMode = enum(c_uint) {
    Undefined = 0x00000000,
    Fifo = 0x00000001,
    FifoRelaxed = 0x00000002,
    Immediate = 0x00000003,
    Mailbox = 0x00000004,
}; // PresentMode

pub const PrimitiveTopology = enum(c_uint) {
    Undefined = 0x00000000,
    PointList = 0x00000001,
    LineList = 0x00000002,
    LineStrip = 0x00000003,
    TriangleList = 0x00000004,
    TriangleStrip = 0x00000005,
}; // PrimitiveTopology

pub const QueryType = enum(c_uint) {
    Occlusion = 0x00000001,
    Timestamp = 0x00000002,
    PipelineStatistics = 0x00030000,
}; // QueryType

pub const QueueWorkDoneStatus = enum(c_uint) {
    Success = 0x00000001,
    InstanceDropped = 0x00000002,
    Error = 0x00000003,
    Unknown = 0x00000004,
}; // QueueWorkDoneStatus

pub const RequestAdapterStatus = enum(c_uint) {
    Success = 0x00000001,
    InstanceDropped = 0x00000002,
    Unavailable = 0x00000003,
    Error = 0x00000004,
    Unknown = 0x00000005,
}; // RequestAdapterStatus

pub const RequestDeviceStatus = enum(c_uint) {
    Success = 0x00000001,
    InstanceDropped = 0x00000002,
    Error = 0x00000003,
    Unknown = 0x00000004,
}; // RequestDeviceStatus

pub const SType = enum(c_uint) {
    ShaderSourceSPIRV = 0x00000001,
    ShaderSourceWGSL = 0x00000002,
    RenderPassMaxDrawCount = 0x00000003,
    SurfaceSourceMetalLayer = 0x00000004,
    SurfaceSourceWindowsHWND = 0x00000005,
    SurfaceSourceXlibWindow = 0x00000006,
    SurfaceSourceWaylandSurface = 0x00000007,
    SurfaceSourceAndroidNativeWindow = 0x00000008,
    SurfaceSourceXCBWindow = 0x00000009,
    DeviceExtras = 0x00030000,
    NativeLimits = 0x00030001,
    PipelineLayoutExtras = 0x00030002,
    ShaderModuleGLSLDescriptor = 0x00030003,
    Reserved30006 = 0x00030004,
    InstanceExtras = 0x00030005,
    BindGroupEntryExtras = 0x00030006,
    BindGroupLayoutEntryExtras = 0x00030007,
    QuerySetDescriptorExtras = 0x00030008,
    SurfaceConfigurationExtras = 0x00030009,
}; // SType

pub const SamplerBindingType = enum(c_uint) {
    BindingNotUsed = 0x00000000,
    Undefined = 0x00000001,
    Filtering = 0x00000002,
    NonFiltering = 0x00000003,
    Comparison = 0x00000004,
}; // SamplerBindingType

pub const Status = enum(c_uint) {
    Success = 0x00000001,
    Error = 0x00000002,
}; // Status

pub const StencilOperation = enum(c_uint) {
    Undefined = 0x00000000,
    Keep = 0x00000001,
    Zero = 0x00000002,
    Replace = 0x00000003,
    Invert = 0x00000004,
    IncrementClamp = 0x00000005,
    DecrementClamp = 0x00000006,
    IncrementWrap = 0x00000007,
    DecrementWrap = 0x00000008,
}; // StencilOperation

pub const StorageTextureAccess = enum(c_uint) {
    BindingNotUsed = 0x00000000,
    Undefined = 0x00000001,
    WriteOnly = 0x00000002,
    ReadOnly = 0x00000003,
    ReadWrite = 0x00000004,
}; // StorageTextureAccess

pub const StoreOp = enum(c_uint) {
    Undefined = 0x00000000,
    Store = 0x00000001,
    Discard = 0x00000002,
}; // StoreOp

pub const SurfaceGetCurrentTextureStatus = enum(c_uint) {
    SuccessOptimal = 0x00000001,
    SuccessSuboptimal = 0x00000002,
    Timeout = 0x00000003,
    Outdated = 0x00000004,
    Lost = 0x00000005,
    OutOfMemory = 0x00000006,
    DeviceLost = 0x00000007,
    Error = 0x00000008,
}; // SurfaceGetCurrentTextureStatus

pub const TextureAspect = enum(c_uint) {
    Undefined = 0x00000000,
    All = 0x00000001,
    StencilOnly = 0x00000002,
    DepthOnly = 0x00000003,
}; // TextureAspect

pub const TextureDimension = enum(c_uint) {
    Undefined = 0x00000000,
    D1 = 0x00000001,
    D2 = 0x00000002,
    D3 = 0x00000003,
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
    R16Unorm = 0x00030000,
    R16Snorm = 0x00030001,
    Rg16Unorm = 0x00030002,
    Rg16Snorm = 0x00030003,
    Rgba16Unorm = 0x00030004,
    Rgba16Snorm = 0x00030005,
    NV12 = 0x00030006,
}; // TextureFormat

pub const TextureSampleType = enum(c_uint) {
    BindingNotUsed = 0x00000000,
    Undefined = 0x00000001,
    Float = 0x00000002,
    UnfilterableFloat = 0x00000003,
    Depth = 0x00000004,
    Sint = 0x00000005,
    Uint = 0x00000006,
}; // TextureSampleType

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
    Uint8 = 0x00000001,
    Uint8x2 = 0x00000002,
    Uint8x4 = 0x00000003,
    Sint8 = 0x00000004,
    Sint8x2 = 0x00000005,
    Sint8x4 = 0x00000006,
    Unorm8 = 0x00000007,
    Unorm8x2 = 0x00000008,
    Unorm8x4 = 0x00000009,
    Snorm8 = 0x0000000A,
    Snorm8x2 = 0x0000000B,
    Snorm8x4 = 0x0000000C,
    Uint16 = 0x0000000D,
    Uint16x2 = 0x0000000E,
    Uint16x4 = 0x0000000F,
    Sint16 = 0x00000010,
    Sint16x2 = 0x00000011,
    Sint16x4 = 0x00000012,
    Unorm16 = 0x00000013,
    Unorm16x2 = 0x00000014,
    Unorm16x4 = 0x00000015,
    Snorm16 = 0x00000016,
    Snorm16x2 = 0x00000017,
    Snorm16x4 = 0x00000018,
    Float16 = 0x00000019,
    Float16x2 = 0x0000001A,
    Float16x4 = 0x0000001B,
    Float32 = 0x0000001C,
    Float32x2 = 0x0000001D,
    Float32x3 = 0x0000001E,
    Float32x4 = 0x0000001F,
    Uint32 = 0x00000020,
    Uint32x2 = 0x00000021,
    Uint32x3 = 0x00000022,
    Uint32x4 = 0x00000023,
    Sint32 = 0x00000024,
    Sint32x2 = 0x00000025,
    Sint32x3 = 0x00000026,
    Sint32x4 = 0x00000027,
    Unorm1010102 = 0x00000028,
    Unorm8x4BGRA = 0x00000029,
}; // VertexFormat

pub const VertexStepMode = enum(c_uint) {
    VertexBufferNotUsed = 0x00000000,
    Undefined = 0x00000001,
    Vertex = 0x00000002,
    Instance = 0x00000003,
}; // VertexStepMode

pub const WaitStatus = enum(c_uint) {
    Success = 0x00000001,
    TimedOut = 0x00000002,
    UnsupportedTimeout = 0x00000003,
    UnsupportedCount = 0x00000004,
    UnsupportedMixedSources = 0x00000005,
}; // WaitStatus

pub const WGSLLanguageFeatureName = enum(c_uint) {
    ReadonlyAndReadwriteStorageTextures = 0x00000001,
    Packed4x8IntegerDotProduct = 0x00000002,
    UnrestrictedPointerParameters = 0x00000003,
    PointerCompositeAccess = 0x00000004,
}; // WGSLLanguageFeatureName
