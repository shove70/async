module package_business;

import buffer;

class Business
{
    mixin(LoadBufferFile!"account.buffer");

    LoginResponse login(string idOrMobile, string password, string UDID, string remoteAddress)
    {
        LoginResponse res = new LoginResponse();

        res.result = 0;
        res.description = "";
        res.userId = 1;
        res.token = "a token";
        res.name = "userName";
        res.mobile = "13700000000";

        return res;
    }
}