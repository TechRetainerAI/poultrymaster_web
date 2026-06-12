using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class HouseService : IHouseService
    {
        private readonly string _connectionString;
        public HouseService(string connectionString)
        {
            _connectionString = connectionString;
        }

        public List<HouseModel> GetAll(string userId, string farmId)
        {
            var list = new List<HouseModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spHouse_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            conn.Open();
            using var reader = cmd.ExecuteReader();
            while (reader.Read())
            {
                list.Add(new HouseModel
                {
                    UserId = reader.GetString(0),
                    FarmId = reader.GetString(1),
                    HouseId = reader.GetInt32(2),
                    HouseName = reader.GetString(3),
                    Capacity = reader.IsDBNull(4) ? null : reader.GetInt32(4),
                    Location = reader.IsDBNull(5) ? null : reader.GetString(5)
                });
            }
            return list;
        }

        public HouseModel? GetById(int id, string userId, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spHouse_GetById", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@HouseId", id);
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            conn.Open();
            using var reader = cmd.ExecuteReader();
            if (reader.Read())
            {
                return new HouseModel
                {
                    UserId = reader.GetString(0),
                    FarmId = reader.GetString(1),
                    HouseId = reader.GetInt32(2),
                    HouseName = reader.GetString(3),
                    Capacity = reader.IsDBNull(4) ? null : reader.GetInt32(4),
                    Location = reader.IsDBNull(5) ? null : reader.GetString(5)
                };
            }
            return null;
        }

        public int Create(HouseModel model)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spHouse_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@UserId", model.UserId);
            cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
            cmd.Parameters.AddWithValue("@HouseName", model.HouseName);
            cmd.Parameters.AddWithValue("@Capacity", (object?)model.Capacity ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Location", (object?)model.Location ?? DBNull.Value);
            conn.Open();
            var result = cmd.ExecuteScalar();
            return Convert.ToInt32(result);
        }

        public void Update(HouseModel model)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spHouse_Update", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@UserId", model.UserId);
            cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
            cmd.Parameters.AddWithValue("@HouseId", model.HouseId);
            cmd.Parameters.AddWithValue("@HouseName", model.HouseName);
            cmd.Parameters.AddWithValue("@Capacity", (object?)model.Capacity ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Location", (object?)model.Location ?? DBNull.Value);
            conn.Open();
            cmd.ExecuteNonQuery();
        }

        public void Delete(int id, string userId, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spHouse_Delete", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@HouseId", id);
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            conn.Open();
            cmd.ExecuteNonQuery();
        }
    }
}
