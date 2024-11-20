pub const DeviceLostReason = enum(c_uint) {
    Unknown = 0,
    Destroyed = 1,
};

pub const AddressMode = enum(c_uint) {
    Repeat = 0,
    MirrorRepeat = 1,
    ClampToEdge = 2,
};

pub const CompareFunction = enum(c_uint) {
    Undefined = 0,
    Never = 1,
    Less = 2,
    LessEqual = 3,
    Greater = 4,
    GreaterEqual = 5,
    Equal = 6,
    NotEqual = 7,
    Always = 8,
};

pub const VertexStepMode = enum(c_uint) {
    Vertex = 0,
    Instance = 1,
    VertexBufferNotUsed = 2,
};

pub const LoadOp = enum(c_uint) {
    Undefined = 0,
    Clear = 1,
    Load = 2,
};

pub const BlendFactor = enum(c_uint) {
    Zero = 0,
    One = 1,
    Src = 2,
    OneMinusSrc = 3,
    SrcAlpha = 4,
    OneMinusSrcAlpha = 5,
    Dst = 6,
    OneMinusDst = 7,
    DstAlpha = 8,
    OneMinusDstAlpha = 9,
    SrcAlphaSaturated = 10,
    Constant = 11,
    OneMinusConstant = 12,
};

pub const CreatePipelineAsyncStatus = enum(c_uint) {
    Success = 0,
    ValidationError = 1,
    InternalError = 2,
    DeviceLost = 3,
    DeviceDestroyed = 4,
    Unknown = 5,
};

pub const QueryType = enum(c_uint) {
    Occlusion = 0,
    Timestamp = 1,
};

pub const BufferBindingType = enum(c_uint) {
    Undefined = 0,
    Uniform = 1,
    Storage = 2,
    ReadOnlyStorage = 3,
};

pub const QueueWorkDoneStatus = enum(c_uint) {
    Success = 0,
    Error = 1,
    Unknown = 2,
    DeviceLost = 3,
};

pub const TextureFormat = enum(c_uint) {
    Undefined = 0,
    R8Unorm = 1,
    R8Snorm = 2,
    R8Uint = 3,
    R8Sint = 4,
    R16Uint = 5,
    R16Sint = 6,
    R16Float = 7,
    RG8Unorm = 8,
    RG8Snorm = 9,
    RG8Uint = 10,
    RG8Sint = 11,
    R32Float = 12,
    R32Uint = 13,
    R32Sint = 14,
    RG16Uint = 15,
    RG16Sint = 16,
    RG16Float = 17,
    RGBA8Unorm = 18,
    RGBA8UnormSrgb = 19,
    RGBA8Snorm = 20,
    RGBA8Uint = 21,
    RGBA8Sint = 22,
    BGRA8Unorm = 23,
    BGRA8UnormSrgb = 24,
    RGB10A2Uint = 25,
    RGB10A2Unorm = 26,
    RG11B10Ufloat = 27,
    RGB9E5Ufloat = 28,
    RG32Float = 29,
    RG32Uint = 30,
    RG32Sint = 31,
    RGBA16Uint = 32,
    RGBA16Sint = 33,
    RGBA16Float = 34,
    RGBA32Float = 35,
    RGBA32Uint = 36,
    RGBA32Sint = 37,
    Stencil8 = 38,
    Depth16Unorm = 39,
    Depth24Plus = 40,
    Depth24PlusStencil8 = 41,
    Depth32Float = 42,
    Depth32FloatStencil8 = 43,
    BC1RGBAUnorm = 44,
    BC1RGBAUnormSrgb = 45,
    BC2RGBAUnorm = 46,
    BC2RGBAUnormSrgb = 47,
    BC3RGBAUnorm = 48,
    BC3RGBAUnormSrgb = 49,
    BC4RUnorm = 50,
    BC4RSnorm = 51,
    BC5RGUnorm = 52,
    BC5RGSnorm = 53,
    BC6HRGBUfloat = 54,
    BC6HRGBFloat = 55,
    BC7RGBAUnorm = 56,
    BC7RGBAUnormSrgb = 57,
    ETC2RGB8Unorm = 58,
    ETC2RGB8UnormSrgb = 59,
    ETC2RGB8A1Unorm = 60,
    ETC2RGB8A1UnormSrgb = 61,
    ETC2RGBA8Unorm = 62,
    ETC2RGBA8UnormSrgb = 63,
    EACR11Unorm = 64,
    EACR11Snorm = 65,
    EACRG11Unorm = 66,
    EACRG11Snorm = 67,
    ASTC4x4Unorm = 68,
    ASTC4x4UnormSrgb = 69,
    ASTC5x4Unorm = 70,
    ASTC5x4UnormSrgb = 71,
    ASTC5x5Unorm = 72,
    ASTC5x5UnormSrgb = 73,
    ASTC6x5Unorm = 74,
    ASTC6x5UnormSrgb = 75,
    ASTC6x6Unorm = 76,
    ASTC6x6UnormSrgb = 77,
    ASTC8x5Unorm = 78,
    ASTC8x5UnormSrgb = 79,
    ASTC8x6Unorm = 80,
    ASTC8x6UnormSrgb = 81,
    ASTC8x8Unorm = 82,
    ASTC8x8UnormSrgb = 83,
    ASTC10x5Unorm = 84,
    ASTC10x5UnormSrgb = 85,
    ASTC10x6Unorm = 86,
    ASTC10x6UnormSrgb = 87,
    ASTC10x8Unorm = 88,
    ASTC10x8UnormSrgb = 89,
    ASTC10x10Unorm = 90,
    ASTC10x10UnormSrgb = 91,
    ASTC12x10Unorm = 92,
    ASTC12x10UnormSrgb = 93,
    ASTC12x12Unorm = 94,
    ASTC12x12UnormSrgb = 95,
};

pub const TextureViewDimension = enum(c_uint) {
    Undefined = 0,
    D1 = 1,
    D2 = 2,
    D2Array = 3,
    Cube = 4,
    CubeArray = 5,
    D3 = 6,
};

pub const VertexFormat = enum(c_uint) {
    Undefined = 0,
    Uint8x2 = 1,
    Uint8x4 = 2,
    Sint8x2 = 3,
    Sint8x4 = 4,
    Unorm8x2 = 5,
    Unorm8x4 = 6,
    Snorm8x2 = 7,
    Snorm8x4 = 8,
    Uint16x2 = 9,
    Uint16x4 = 10,
    Sint16x2 = 11,
    Sint16x4 = 12,
    Unorm16x2 = 13,
    Unorm16x4 = 14,
    Snorm16x2 = 15,
    Snorm16x4 = 16,
    Float16x2 = 17,
    Float16x4 = 18,
    Float32 = 19,
    Float32x2 = 20,
    Float32x3 = 21,
    Float32x4 = 22,
    Uint32 = 23,
    Uint32x2 = 24,
    Uint32x3 = 25,
    Uint32x4 = 26,
    Sint32 = 27,
    Sint32x2 = 28,
    Sint32x3 = 29,
    Sint32x4 = 30,
};

pub const StencilOperation = enum(c_uint) {
    Keep = 0,
    Zero = 1,
    Replace = 2,
    Invert = 3,
    IncrementClamp = 4,
    DecrementClamp = 5,
    IncrementWrap = 6,
    DecrementWrap = 7,
};

pub const PowerPreference = enum(c_uint) {
    Undefined = 0,
    LowPower = 1,
    HighPerformance = 2,
};

pub const SurfaceGetCurrentTextureStatus = enum(c_uint) {
    Success = 0,
    Timeout = 1,
    Outdated = 2,
    Lost = 3,
    OutOfMemory = 4,
    DeviceLost = 5,
};

pub const WGSLFeatureName = enum(c_uint) {
    Undefined = 0,
    ReadonlyAndReadwriteStorageTextures = 1,
    Packed4x8IntegerDotProduct = 2,
    UnrestrictedPointerParameters = 3,
    PointerCompositeAccess = 4,
};

pub const ErrorType = enum(c_uint) {
    NoError = 0,
    Validation = 1,
    OutOfMemory = 2,
    Internal = 3,
    Unknown = 4,
    DeviceLost = 5,
};

pub const RequestDeviceStatus = enum(c_uint) {
    Success = 0,
    Error = 1,
    Unknown = 2,
};

pub const CompositeAlphaMode = enum(c_uint) {
    Auto = 0,
    Opaque = 1,
    Premultiplied = 2,
    Unpremultiplied = 3,
    Inherit = 4,
};

pub const BufferMapAsyncStatus = enum(c_uint) {
    Success = 0,
    ValidationError = 1,
    Unknown = 2,
    DeviceLost = 3,
    DestroyedBeforeCallback = 4,
    UnmappedBeforeCallback = 5,
    MappingAlreadyPending = 6,
    OffsetOutOfRange = 7,
    SizeOutOfRange = 8,
};

pub const MipmapFilterMode = enum(c_uint) {
    Nearest = 0,
    Linear = 1,
};

pub const StoreOp = enum(c_uint) {
    Undefined = 0,
    Store = 1,
    Discard = 2,
};

pub const TextureDimension = enum(c_uint) {
    D1 = 0,
    D2 = 1,
    D3 = 2,
};

pub const StorageTextureAccess = enum(c_uint) {
    Undefined = 0,
    WriteOnly = 1,
    ReadOnly = 2,
    ReadWrite = 3,
};

pub const SamplerBindingType = enum(c_uint) {
    Undefined = 0,
    Filtering = 1,
    NonFiltering = 2,
    Comparison = 3,
};

pub const TextureSampleType = enum(c_uint) {
    Undefined = 0,
    Float = 1,
    UnfilterableFloat = 2,
    Depth = 3,
    Sint = 4,
    Uint = 5,
};

pub const ErrorFilter = enum(c_uint) {
    Validation = 0,
    OutOfMemory = 1,
    Internal = 2,
};

pub const FrontFace = enum(c_uint) {
    CCW = 0,
    CW = 1,
};

pub const PresentMode = enum(c_uint) {
    Fifo = 0,
    FifoRelaxed = 1,
    Immediate = 2,
    Mailbox = 3,
};

pub const PrimitiveTopology = enum(c_uint) {
    PointList = 0,
    LineList = 1,
    LineStrip = 2,
    TriangleList = 3,
    TriangleStrip = 4,
};

pub const FilterMode = enum(c_uint) {
    Nearest = 0,
    Linear = 1,
};

pub const BlendOperation = enum(c_uint) {
    Add = 0,
    Subtract = 1,
    ReverseSubtract = 2,
    Min = 3,
    Max = 4,
};

pub const BackendType = enum(c_uint) {
    Undefined = 0,
    Null = 1,
    WebGPU = 2,
    D3D11 = 3,
    D3D12 = 4,
    Metal = 5,
    Vulkan = 6,
    OpenGL = 7,
    OpenGLES = 8,
};

pub const IndexFormat = enum(c_uint) {
    Undefined = 0,
    Uint16 = 1,
    Uint32 = 2,
};

pub const AdapterType = enum(c_uint) {
    DiscreteGPU = 0,
    IntegratedGPU = 1,
    CPU = 2,
    Unknown = 3,
};

pub const BufferMapState = enum(c_uint) {
    Unmapped = 0,
    Pending = 1,
    Mapped = 2,
};

pub const CompilationInfoRequestStatus = enum(c_uint) {
    Success = 0,
    Error = 1,
    DeviceLost = 2,
    Unknown = 3,
};

pub const TextureAspect = enum(c_uint) {
    All = 0,
    StencilOnly = 1,
    DepthOnly = 2,
};

pub const CompilationMessageType = enum(c_uint) {
    Error = 0,
    Warning = 1,
    Info = 2,
};

pub const SType = enum(c_uint) {
    Invalid = 0,
    SurfaceDescriptorFromMetalLayer = 1,
    SurfaceDescriptorFromWindowsHWND = 2,
    SurfaceDescriptorFromXlibWindow = 3,
    SurfaceDescriptorFromCanvasHTMLSelector = 4,
    ShaderModuleSPIRVDescriptor = 5,
    ShaderModuleWGSLDescriptor = 6,
    PrimitiveDepthClipControl = 7,
    SurfaceDescriptorFromWaylandSurface = 8,
    SurfaceDescriptorFromAndroidNativeWindow = 9,
    SurfaceDescriptorFromXcbWindow = 10,
    RenderPassDescriptorMaxDrawCount = 11,
};

pub const RequestAdapterStatus = enum(c_uint) {
    Success = 0,
    Unavailable = 1,
    Error = 2,
    Unknown = 3,
};

pub const CullMode = enum(c_uint) {
    None = 0,
    Front = 1,
    Back = 2,
};

pub const FeatureName = enum(c_uint) {
    Undefined = 0,
    DepthClipControl = 1,
    Depth32FloatStencil8 = 2,
    TimestampQuery = 3,
    TextureCompressionBC = 4,
    TextureCompressionETC2 = 5,
    TextureCompressionASTC = 6,
    IndirectFirstInstance = 7,
    ShaderF16 = 8,
    RG11B10UfloatRenderable = 9,
    BGRA8UnormStorage = 10,
    Float32Filterable = 11,
};
