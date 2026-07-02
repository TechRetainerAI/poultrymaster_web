using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Identity;
using User.Management.Data;
using User.Management.Data.Models;
using User.Management.Service.Models;
using User.Management.Service.Models.Authentication.User;

namespace User.Management.Service.Services
{
    public class CompanyService : ICompanyService
    {
        private readonly ICompanyDAL _dal;
        private readonly IUserManagement _userManagement;
        private readonly UserManager<ApplicationUser> _userManager;

        public CompanyService(
            ICompanyDAL dal,
            IUserManagement userManagement,
            UserManager<ApplicationUser> userManager)
        {
            _dal = dal;
            _userManagement = userManagement;
            _userManager = userManager;
        }

        public async Task<ApiResponse<List<CompanyResponse>>> GetMineAsync(string userId)
        {
            var list = await _dal.GetByUserIdAsync(userId);
            return new ApiResponse<List<CompanyResponse>>
            {
                IsSuccess = true,
                StatusCode = 200,
                Response = list,
                Message = $"Found {list.Count} companies",
            };
        }

        public async Task<ApiResponse<CompanyResponse>> CreateAsync(string userId, CreateCompanyRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.Name))
            {
                return new ApiResponse<CompanyResponse>
                {
                    IsSuccess = false,
                    StatusCode = 400,
                    Message = "Company name is required.",
                };
            }

            var farmId = Guid.NewGuid().ToString();
            var company = await _dal.CreateAsync(farmId, req, userId);

            return new ApiResponse<CompanyResponse>
            {
                IsSuccess = true,
                StatusCode = 201,
                Response = company,
                Message = "Company created",
            };
        }

        public async Task<ApiResponse<CompanyResponse>> UpdateAsync(string userId, string farmId, CreateCompanyRequest req)
        {
            if (string.IsNullOrWhiteSpace(farmId))
            {
                return new ApiResponse<CompanyResponse> { IsSuccess = false, StatusCode = 400, Message = "Company id is required." };
            }
            if (string.IsNullOrWhiteSpace(req?.Name))
            {
                return new ApiResponse<CompanyResponse> { IsSuccess = false, StatusCode = 400, Message = "Company name is required." };
            }

            // Only a member of the company may edit it.
            if (!await _dal.IsMemberAsync(userId, farmId))
            {
                return new ApiResponse<CompanyResponse> { IsSuccess = false, StatusCode = 403, Message = "You do not have access to this company." };
            }

            await _dal.UpdateAsync(farmId, req);
            var updated = await _dal.GetByIdAsync(farmId, userId);

            return new ApiResponse<CompanyResponse>
            {
                IsSuccess = true,
                StatusCode = 200,
                Response = updated,
                Message = "Company updated",
            };
        }

        public async Task<ApiResponse<LoginResponse>> SwitchAsync(string userId, string targetFarmId)
        {
            if (string.IsNullOrWhiteSpace(targetFarmId))
            {
                return new ApiResponse<LoginResponse>
                {
                    IsSuccess = false,
                    StatusCode = 400,
                    Message = "FarmId is required.",
                };
            }

            var isMember = await _dal.IsMemberAsync(userId, targetFarmId);
            if (!isMember)
            {
                return new ApiResponse<LoginResponse>
                {
                    IsSuccess = false,
                    StatusCode = 403,
                    Message = "You are not a member of the target company.",
                };
            }

            var company = await _dal.GetByIdAsync(targetFarmId, userId);
            if (company == null)
            {
                return new ApiResponse<LoginResponse>
                {
                    IsSuccess = false,
                    StatusCode = 404,
                    Message = "Company not found.",
                };
            }

            var user = await _userManager.FindByIdAsync(userId);
            if (user == null)
            {
                return new ApiResponse<LoginResponse>
                {
                    IsSuccess = false,
                    StatusCode = 404,
                    Message = "User not found.",
                };
            }

            // Persist the new active farm so future logins land on the same one.
            user.FarmId = company.FarmId;
            user.FarmName = company.Name;
            await _userManager.UpdateAsync(user);

            // Re-issue JWT with new FarmId / FarmName claims.
            return await _userManagement.GetJwtTokenAsync(user);
        }
    }
}
