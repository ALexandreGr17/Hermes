pub const SIGNATURE: [4]u8 = [4]u8{'H', 'E', 'R', 'M'};

pub const AdvertismentMsg = extern struct {
    signature: [4]u8 = SIGNATURE,
    port: u16,
};

pub const NewConnMsg = struct {
    port: u16,
    ip: u32
};
